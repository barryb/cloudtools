#!/bin/sh

# The script updates installed packages and adds any required ones for backing up the RDS server.
# Some initial config, including installing git and the cloud credentials needs to be done prior to this
# ideally, by using the user_data file for amazon cloud servers


LOGFILE="/tmp/setup.log"

(
	echo "Initial Host Setup - $(date -R)!"
	# Don't bother installing gem docs
	echo "gem: --no-ri --no-rdoc" >> ~/.gemrc
	
	SCRIPT_DIR=/usr/local/scripts
	CT_PATH=$REPOS_PATH/cloudtools
	
	mkdir -p "$SCRIPT_DIR/rds-backup"
	for f in $(ls -d /usr/local/repos/cloudtools/host-recipes/rds-backup/scripts/*); do
		ln -s $f /usr/local/scripts/rds-backup;
	done
	# ln -s $CT_PATH/scripts/* $SCRIPT_DIR/rds-backup
		
	# Add relevant ssh public keys for access	
	cat /usr/local/repos/cloudtools/public_keys/bb_*id_rsa.pub >> ~ec2-user/.ssh/authorized_keys
	
	# Remove ls coloring
	echo "unalias ls" >> ~ec2-user/.bash_profile
	
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
	
	# Prevent ssh timeouts for routers that dump idle sessions too quickly
	echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
	/etc/init.d/sshd restart
	
	echo "Initial Setup Done -  $(date -R)!"
	
) >> ${LOGFILE}
