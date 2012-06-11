#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'right_aws'
require 'cloudfiles'
require 'date'

# creds will contain access credentials for both Amazon and Rackspace services
# config will contain options applicable to the backup job

# Delete objects older than this in the backup bucket
# Currently only pruning rackspace
# Need to add S3 too

max_object_age = 60

# Wait this long for restore from rds snapshot in minutes
timeout_wait_for_rds = 40


creds = YAML::load( File.open( '/etc/cloudtools/cloud_creds.yml' ) )
config = YAML::load( File.open( '/etc/cloudtools/rds_config.yml' ) )

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];
rsp_key=creds["rsp_key"];
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

current_instances = rds.describe_db_instances()

result =  current_instances.select { |i| i[:aws_id] == temp_db_id }
matched = result.count

if matched > 0
        puts "Temp database \'#{temp_db_id}\' already exists"
        puts "Either fix the config, or rename/remove the database"
        exit 1
end

result = rds.describe_db_instances(orig_db_id)
restorable_time = result.first[:latest_restorable_time]


dump_filename="#{orig_db_id}-#{database_name}-#{restorable_time}.sql"
dump_gzipname="#{dump_filename}.gz"


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
	{ :use_latest_restorable_time=>"true",
	  :instance_class=>"db.m1.small" }
	)
	
	
	
#	
# Wait for 10 minutes, then check every minute before giving up after another ten minutes
#
timeout = timeout_wait_for_rds - 10

puts "Waiting an initial ten minutes before checking if DB is up..."
puts "Will then wait for a further #{timeout} minutes checking at 1 minute intervals"

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

# Remove IP from the backup group - we can add it back on next run
# Might be running from a different ip next time!

result = rds.revoke_db_security_group_ingress(rds_security_group, :cidrip => my_cidr)
sleep 1
puts "Database Server Deleted"
puts "IP removed from backup security group"

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

cf = CloudFiles::Connection.new(rsp_key, rsp_secret, true, false)

container = cf.container(rackspace_container_name)

# Delete objects older than max_object_age

filelist = container.objects_detail()

filelist.each { |key, value| 
	modified = value[:last_modified]
	age = (DateTime.now - DateTime.strptime("#{value[:last_modified]}",'%Y-%m-%dT%H:%M:%S%z')).to_i
	if age >= max_object_age
		puts "Deleting #{key}"
		container.delete_object("#{key}")
	end
	}

# Upload new database backup

puts "Uploading file to Cloudfiles (Rackspace)"

object = container.create_object(dump_gzipname)
object.load_from_filename("#{scratch_dir}/#{dump_gzipname}")

puts "Done"
puts "Shutting down in 1 minute"
fork { system("/sbin/shutdown -P +1") }
puts "Goodbye cruel world!"
exit 1


