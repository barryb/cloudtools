#!/usr/bin/env ruby

require 'yaml'

valid_envs = ['production', 'development', 'other']

my_config = "test.yml"

my_env = ENV['APPENV'].nil? ? 'development' : ENV['APPENV']

if valid_envs.index(my_env).nil?
	puts "#{my_env} is not a valid environment"
	exit 0
else
	puts "Setting environment to: #{my_env}"

end

exit 1

#YAML.load_file(my_config)


