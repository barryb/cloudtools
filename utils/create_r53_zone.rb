#!/usr/bin/ruby

require 'rubygems'
require 'right_aws'
require 'yaml'
require 'trollop'
require 'zonefile'

creds = YAML::load( File.open( '/etc/cloudtools/cloud_creds.yml' ) )

aws_key=creds["aws_key"];
aws_secret=creds["aws_secret"];

r53 = RightAws::Route53Interface.new(
	aws_key,
	aws_secret,
  	{:logger => Logger.new('/tmp/ec2.log')}
  	)


zf = Zonefile.from_file('./q-stream.net.zone')

origin = zf.soa[:origin].downcase

record_sets = []

zf.mx.each do |record|
	record_sets << {
		:name => "mail.#{origin}",
		:type => "MX",
		:ttl => record[:ttl],
		:resource_records => "#{record[:pri]} #{record[:host]}"
	}
end
p record_sets
#exit 1
result = r53.create_resource_record_sets("/hostedzone/Z2BRWRE98GQIBE", record_sets, 'The MX Records')

p result


exit 1


aws_zone_config = {
	:name => zf.soa[:origin].downcase,
	:config => {
		:comment => ""
	}
}


  	
result = r53.create_hosted_zone(aws_zone_config)

aws_id = result[:aws_id]

puts "ID: #{aws_id}"

p result

exit 1
  	
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