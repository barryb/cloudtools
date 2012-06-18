#!/usr/bin/ruby

require 'rubygems'
require 'right_aws'
require 'yaml'
require 'trollop'

creds = YAML::load( File.open( '/etc/cloudtools/cloud_creds.yml' ) )

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];

p aws_key
p aws_secret

exit 1;

r53 = RightAws::Ec2.new(
	aws_key,
	aws_secret,
  	{:logger => Logger.new('/tmp/ec2.log')}
  	)
  	
ARGV.each do|i|
	# Assume each argument is an instance ID
	# Check that it exists and is in a stopped state
	
	matching_instances = ec2.describe_instances(
		:filters => {
			'instance-state-code' => 80,
			'instance-id' => i
			})
			
	if matching_instances.count == 1
		puts "Starting instance #{i}"
		ec2.start_instances(i)
	else
		puts "Did NOT find stopped instance #{i}"
	end
end