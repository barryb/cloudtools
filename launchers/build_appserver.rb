#!/usr/bin/ruby

require 'rubygems'
require 'right_aws'
require 'yaml'

creds = YAML::load( File.open( '/etc/cloudtools/cloud_creds.yml' ) )

server_name="bb-app1"
server_creator="bb"

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];

repos_path="/usr/local/repos"
cloud_dir="/etc/cloudtools"
apps_dir="/opt/apps"

cloud_config="#{cloud_dir}/cloud_creds.yml"

cloud_yaml = <<EOS
aws_key: #{aws_key}
aws_secret: #{aws_secret}
EOS

rsa_file = File.expand_path "~/.ssh/qs_deplay_rsa"
id_rsa = File.read(rsa_file)




initial_config_script = <<EOS
#!/bin/sh
(

	# Prevent ssh timeouts for routers that dump idle sessions too quickly
	echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
	/etc/init.d/sshd restart
	
	export REPOS_PATH="#{repos_path}"
	export CLOUD_DIR="#{cloud_dir}"
	export APPS_DIR="#{cloud_dir}"
	
	echo "Starting Initial Configuration - The time is now $(date -R)!"
	mkdir -p "#{cloud_dir}"
	mkdir -p "#{apps_dir}"
	
	echo "#{cloud_yaml}" >> #{cloud_config}
	echo "#{id_rsa}" >> ~/.ssh/id_rsa
	yum -y install git
	mkdir -p #{repos_path}
	cd #{repos_path}
	
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


