#!/bin/sh

LOGFILE="/tmp/boot.log"

(
	echo "Initial Host Setup - $(date -R)!"
	# Don't bother installing gem docs
	echo "gem: --no-ri --no-rdoc" >> ~/.gemrc
	
	yum -y update

	# Need Mysqldump for backing update
	
	yum -y install mysql51
	
	yum -y install rubygems
	gem update --system
	
	# The following are required for the nokogiri gem
	yum install -y gcc make ruby-devel libxml2 libxml2-devel libxslt libxslt-devel
	
	gem install right_aws
	gem sources -a http://gemcutter.org/
	gem install cloudfiles 
	
	# Add relevant ssh public keys for access	
	cat /usr/local/repos/cloudfiles/public_keys/bb-id_rsa.pub >> ~ec2-user/.ssh/authorized_keys
	
	# Remove ls coloring
	echo "unalias ls" >> ~ec2-user/.bash_profile
	
	# Prevent ssh timeouts for routers that dump idle sessions too quickly
	echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
	/etc/init.d/sshd restart
	
	echo "Initial Setup Done -  $(date -R)!"
	
) >> ${LOGFILE}