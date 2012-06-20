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
  	{:logger => Logger.new('/tmp/r53.log')}
  	)

record_sets = []

zf = Zonefile.from_file('./q-stream.net.zone')
origin = zf.soa[:origin].downcase

# Do MX Records
# Route 53 only lets you have a single MX record set with multiple host/priority pairs

res_recs = []
mx_ttl = zf.soa[:ttl]

zf.mx.each do |record|
	res_recs << "#{record[:pri]} #{record[:host]}"
	mx_ttl = record[:ttl]
end

record_sets << {
	:name => origin,
	:ttl => mx_ttl,
	:type => "MX",
	:resource_records => res_recs
}

# A records 
# This will break if there are multiple IPs for a hostname
# zonefile gem doesn't really deal with these

zf.a.each do |record|
	record_sets << {
		:name => record[:name] == '@' ? origin : "#{record[:name]}.#{origin}",
		:ttl => record[:ttl],
		:type => "A",
		:resource_records => record[:host] == '@' ? ["#{origin}"] : ["#{record[:host]}"]
	}

end


# CNAMES

zf.cname.each do |record|
	record_sets << {
		:name => record[:name] == '@' ? origin : "#{record[:name]}.#{origin}",
		:ttl => record[:ttl],
		:type => "CNAME",
		:resource_records => record[:host] == '@' ? ["#{origin}"] : ["#{record[:host]}"]
	}

end

p record_sets


result = r53.create_resource_record_sets("/hostedzone/Z2BRWRE98GQIBE", record_sets)

#p result


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