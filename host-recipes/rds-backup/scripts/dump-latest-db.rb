#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'right_aws'
require 'cloudfiles'

# creds will contain access credentials for both Amazon and Rackspace services
# config will contain options applicable to the backup job

creds = YAML::load( File.open( '/etc/cloudtools/cloud_creds.yml' ) )
config = YAML::load( File.open( '/etc/cloudtools/rds_backup_cfg.yml' ) )

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];
rsp_key=creds["rsp_key_key"];
rsp_secret=creds["rsp_secret"];

rds = RightAws::RdsInterface.new(
	aws_key,
	aws_secret,
  	{:logger => Logger.new('/tmp/rds.log')}
  )
  
# Need to validate all of the below are of sound construction!!
  
orig_db_id = config['orig_db_id']
rds_security_group = config['rds_security_group']
new_master_password = config['new_master_password']
database_name = config['database_name']
scratch_dir = config['scratch']
s3_bucket_name = config['s3_bucket_name']
rackspace_container_name = config['rackspace_container_name']


# Need to make sure this doesn't exist and exit if it does
# since this gets deleted at the end of the process

temp_db_id = "#{orig_db_id}-tempsnap"

#result = rds.describe_db_instances('nosuchdb')
#puts result.inspect
#exit 1

result = rds.describe_db_instances(orig_db_id)
restorable_time = result.first[:latest_restorable_time]


dump_filename="#{orig_db_id}-#{database_name}-#{restorable_time}.sql"
dump_gzipname="#{dump_filename}.gz"


db_save_dir="/mnt/db_backups"
db_save_base="#{orig_db_id}-#{database_name}-#{restorable_time}.sql"
db_save_file="#{db_save_dir}/#{db_save_base}"
db_save_zip="#{db_save_file}.gz"


#exit 1


#
# Extend the class to yield a power status
#

class RightAws::RdsInterface
	def power_status(aws_id)
		begin
			result = describe_db_instances(aws_id)
			result.first[:status]
		rescue
			"Unknown Error"
		end		
	end
end


#
# find my IP address in CIDR
#
my_cidr= IPSocket.getaddress(Socket.gethostname) + "/32"


#
# check if this host is already authorized in the RDS security group
#
result = rds.describe_db_security_groups(rds_security_group)
ip_ranges = result.last[:ip_ranges]

ip_authorized = false
ip_ranges.each do |line|
	ip_authorized = true if line[:cidrip] == my_cidr && line[:status].downcase == "authorized"
end

if ip_authorized == false
	puts "Adding IP to security group"
	rds.authorize_db_security_group_ingress(rds_security_group, :cidrip => my_cidr)
else
	puts "Already a member of security group: #{rds_security_group}"
end




#
# Create a temporary database based on last snapshot available
#
puts "Creating new RDS instance from latest available snapshot"

result = rds.restore_db_instance_to_point_in_time(
	orig_db_id,
	temp_db_id, 
	{ :use_latest_restorable_time=>"true" }
	)
	
	
	
#	
# Wait for 10 minutes, then check every minute before giving up after another ten minutes
#
timeout = 20
puts "Waiting an initial ten minutes before checking if DB is up..."
puts "Will wait for a further 20 minutes checking at 1 minute intervals"

sleep 600
until timeout == 0 || rds.power_status(temp_db_id) == "available"
	puts "waiting for #{temp_db_id}"
	sleep 60
	timeout -= 1
end

if rds.power_status(temp_db_id) == "available"
	puts "Available"
else
	puts "Not available"
	exit 0
end



#
# Change password and security group
#
puts "Changing master password and security groups"

result = rds.modify_db_instance(
	temp_db_id, 
	:master_user_password => new_master_password,
	:db_security_groups => ['default', rds_security_group] )

sleep 60
puts "Waiting 60s before dumping database"


result = rds.describe_db_instances(temp_db_id)
endpoint = result.first[:endpoint_address]
username = result.first[:master_username]
puts new_master_password

line="/usr/bin/mysqldump -h #{endpoint} -u #{username} -p#{new_master_password} #{database_name} > #{scratch_dir}/#{dump_filename}"


puts line


puts "Starting DB dump"
system(line)
puts "Backup Finished"

puts "Preparing to delete RDS Instance: #{temp_db_id}"
sleep 5
result = rds.delete_db_instance(temp_db_id, :skip_final_snapshot => true)
sleep 1
puts "Database Server Deleted"

puts "Preparing to zip database"
sleep 5
line="/bin/gzip #{scratch_dir}/#{dump_filename}"
system(line)

puts "Database zipped"

puts "Preparing to upload to S3"

s3 = RightAws::S3Interface.new(
	aws_key,
	aws_secret,
  {:logger => Logger.new('/tmp/s3.log')})
  
  
puts "Uploading file to S3..."
  
s3.put(s3_bucket_name, dump_gzipname, File.open("#{scratch_dir}/#{dump_gzipname}"))

puts "Done."

# Last parameter set to true would mean use rackspace private addressing, but we are not local to rackspace

cf = CloudFiles::Connection.new(rds_key, rds_secret, true, false)

container = cf.container(rackspace_container_name)

puts "Uploading file to Cloudfiles (Rackspace)"

object = container.create_object(dump_gzipname)
object.load_from_filename("#{scratch_dir}/#{dump_gzipname}")

puts "Done"

exit 1

