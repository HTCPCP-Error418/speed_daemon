#!/bin/bash

function error_check {
	echo "This script will setup the system for speedtest"
	echo "This may include installation of software and creation of directories"
	read -p "Continue setup? [Y/n] " cont

	#default to "y"
	if [[ -z $cont ]]; then
		cont=y
	fi

	#if anything other than "y" entered, exit setup
	if [[ $cont != "y" && $cont != "Y" ]]; then
		echo "Setup cancelled..."
		exit 1
	fi

	#check for root permissions
	if [[ ! $(id -u) == 0 ]]; then
		echo "This script must be run as root, please elevate permissions and try again."
		exit 1
	fi
}

#check for program dependencies
function depend_check {
	which ruby
	if [[ $? != 0 ]]; then
		apt install ruby -y
	fi

	which speedtest-cli
	if [[ $? != 0 ]]; then
		apt install speedtest-cli -y
	fi

	which mysql
	if [[ $? != 0 ]]; then
		apt install mysql-server -y
	fi
}

#move program files to needed directories
function move_program {
	if [[ -f ./speedtestd.rb ]]; then
		mv ./speedtestd.rb /usr/local/lib/
		chmod u+x /usr/local/lib/speedtestd.rb
	else
		echo "Unable to locate speedtestd.rb, please run this script from the same directory"
		exit 1
	fi

	if [[ -f ./speedtest.rb ]]; then
		mv ./speedtest.rb /usr/local/bin
		chmod u+x /usr/local/bin/speedtest.rb
	else
		echo "Unable to locate speedtest.rb, please run this script from the same directory"
		exit 1
	fi
}

#create log directory and log file
function logs {
	mkdir -p /var/log/speedtest/
	touch /var/log/speedtest/speedtest.log
	chmod 0755 /var/log/speedtest/
	chmod 0644 /var/log/speedtest/speedtest.log
}

#configure logrotate to rotate speedtest logs
function logrotate {
	cat <<-"EOF" > /etc/logrotate.d/speedtest
		/var/log/speedtest/speedtest.log {
		  rotate 8
		  weekly
		  compress
		  missingok
		  notifempty
		}
	EOF
}

#create speedtest.conf file in /usr/local/share -- is this necessary?
function conf {
#	read -p "Please enter a name for the MySQL database: " db_name
#	read -p "Please enter a name for the MySQL table: " tbl_name
#	read -p "Please enter the Speedtest Server ID to use (https://www.speedtestserver.com/): " server_id
#	echo "db=$db_name" >> /usr/local/share/speedtest.conf
#	echo "tbl=$tbl_name" >> /usr/local/share/speedtest.conf
#	echo "server_id=$server_id" >> /usr/local/share/speedtest.conf
#
	echo "Instructions for setting up the MySQL database are available in the README for this repo."
}

########
# MAIN #
########

error_check
depend_check
move_program
logs
logrotate
conf
