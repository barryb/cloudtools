#!/bin/sh

LOGFILE="/tmp/boot.log"

(
	echo "Initial Host Setup - $(date -R)!"
	# Don't bother installing gem docs
	echo "gem: --no-ri --no-rdoc" >> ~/.gemrc
	
	yum -y update
	yum -y install rubygems
	gem update --system
	
	# The following are required for the nokogiri gem
	yum install -y gcc make ruby-devel libxml2 libxml2-devel libxslt libxslt-devel
	
	gem install right_aws
	gem sources -a http://gemcutter.org/
	gem install cloudfiles 
	
	# Prevent ssh timeouts for routers that dump idle sessions too quickly
	echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
	
	echo "Initial Setup Done -  $(date -R)!"
	
) >> ${LOGFILE}