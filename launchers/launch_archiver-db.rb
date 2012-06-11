#!/usr/bin/ruby

require 'rubygems'
require 'right_aws'
require 'yaml'

valid_envs = ['production', 'development']

my_config = "test.yml"

my_env = ENV['APPENV'].nil? ? 'development' : ENV['APPENV']

if valid_envs.index(my_env).nil?
	puts "#{my_env} is not a valid environment"
	exit 0
else
	puts "Setting environment to: #{my_env}"

end

YAML.load_file(my_config)[my_env].each do |key, val|
    puts "#{key}= #{val}"
end

#p config

exit 1

user_conf_file = File.expand_path "~/.cloudtools/cloud_creds.yml"
global_conf_file = '/etc/cloudtools/cloud_creds.yml'

if File.exist? user_conf_file
	puts "Using user creds file"
	creds = YAML::load( File.open( user_conf_file ) )
elsif File.exist? global_conf_file
	puts "Using global creds file"
	creds = YAML::load( File.open( global_conf_file ) )
else
	puts "NO creds file found - Exiting."
	exit 0
end

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];
rsp_key=creds["rsp_key"];
rsp_secret=creds["rsp_secret"];

ec2 = RightAws::Ec2.new(
	aws_key,
	aws_secret,
  	{:logger => Logger.new('/tmp/ec2.log')}
  	)
  	
matching_instances = ec2.describe_instances(
		:filters => {
			'instance-state-code' => 80
			})
			
#p matching_instances



if ARGV.count != 1
	puts "Usage: #{$0} SERVER_NAME"
	exit 0
end

server_name=ARGV.first
server_creator="bb"
repos_source='https://github.com/barryb/cloudtools.git'

puts "Server name: #{server_name}"
exit 1


repos_path="/usr/local/repos"
cloud_dir="/etc/cloudtools"

cloud_config="#{cloud_dir}/cloud_creds.yml"
rds_config="#{cloud_dir}/rds_config.yml"

cloud_yaml = <<EOS
aws_key: #{aws_key}
aws_secret: #{aws_secret}
rsp_key: #{rsp_key}
rsp_secret: #{rsp_secret}
EOS

rds_yaml = <<EOS
orig_db_id: dev3
rds_security_group: backup
new_master_password: beynac55
database_name: spaceded
scratch: /media/ephemeral0
s3_bucket_name: db_backups.qstream
rackspace_container_name: db_backups.qstream
EOS


initial_config_script = <<EOS
#!/bin/sh
(
	export REPOS_PATH="#{repos_path}"
	EXPORT CLOUD_DIR="#{cloud_dir}"
	echo "Starting Initial Configuration - The time is now $(date -R)!"
	mkdir -p "#{cloud_dir}"
	echo "#{cloud_yaml}" >> #{cloud_config}
	echo "#{rds_yaml}" >> #{rds_config}
	yum -y install git
	mkdir -p #{repos_path}
	cd #{repos_path}
	git clone #{repos_source}
	#{repos_path}/cloudtools/host-recipes/rds-backup/initial-config.sh	
) >> /tmp/setup.log
EOS

ec2 = RightAws::Ec2.new(
	aws_key,
	aws_secret,
  	{:logger => Logger.new('/tmp/ec2.log')}
  	)
  	
instances = ec2.run_instances('ami-e565ba8c',
	min = 1,
	max = 1,
	groups = ['default'],
	key = 'bp-keypair',
	user_data = initial_config_script,
	"public",
	"m1.small",
	kernel = nil,
	ramdisk = nil,
	zone = nil,
	monitoring = nil,
	subnet_id = nil,
	disable_api_termination = nil,
	instance_initiated_shutdown_behaviour = nil,
	block_device_mappings = [
		{	
		:virtual_name => 'ephemeral0',
        :device_name=>"/dev/sdb"
        }	
	])
	
	
instance_id = instances.first[:aws_instance_id]

# Need to wait until the instance is available - right_aws craps out if it's not
# without the wait, sometimes it works, sometimes it doesn't depending on how slow aws is

matched=0
while matched == 0
	sleep 5
	current_instances = ec2.describe_instances
	result =  current_instances.select { |i| i[:aws_instance_id] == instance_id }
	matched = result.count
end

#while ec2.describe_instances(instance_id).count <= 0
#	puts "Waiting for instance to be available"
#	sleep 5
#end


ec2.create_tags(instance_id, 
	{"Name" => server_name, 
	"qs_owner" => server_creator}
	) 

puts "Waiting 60 seconds for instance to start"
$stdout.sync = true
60.times do
	sleep 1
	print '.'
end

puts ' '

dns_name = ''
instances = ec2.describe_instances(instance_id)
dns_name = instances.first[:dns_name]

while dns_name.empty?
	print "Not ready yet, waiting another 15 seconds "
	15.times do
		sleep 1
		print '.'
	end
	puts ' '
	instances = ec2.describe_instances(instance_id)
	dns_name = instances.first[:dns_name]
end

puts "DNS name: #{dns_name}"
puts "AWS ID: #{instance_id}"

puts "Use this to connect: ssh ec2-user@#{dns_name}"
puts "Check the log in /tmp/boot.log"

exit 1


