#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'

#hash table to store options and set defaults
$options = {
	:mysql_db => "",
	:mysql_tbl => "",
	:server => 6421,
	:interval => 10,
	:logfile => "/var/log/speetest.log"
}

#hash table to store test results
$results = {
	:date => "",
	:time => "",
	:ping => 0,
	:down => 0,
	:up => 0
}

#some basic error checking
def error_check
	#make sure database and table name are specified
	if ($options[:mysql_db].empty? or $options[:mysql_tbl].empty?)
		STDERR.puts " [!] MySQL database and table names are required, exiting..."
		STDERR.puts ""
		exit(1)
	end

	#test if mysql is running
	`systemctl status mysql > /dev/null`			#systemctl seems to have errors checking the status (sometimes) if this is't run first...
	`systemctl is-active --quiet mysql`
	if $?.exitstatus != 0
		STDERR.puts " [!] MySQL server does not seem to be running, exiting..."
		STDERR.puts ""
		exit(1)
	end

	#check if specified table exists
	table_check = `mysql --execute="SELECT IF( EXISTS( SELECT * FROM information_schema.tables WHERE table_schema = \\\"#{$options[:mysql_db]}\\\" AND table_name = \\\"#{$options[:mysql_tbl]}\\\"), 1, 0);"`
	table_check = table_check.split(')')			#separate echoed query from SQL server from query result (1 == table exists)
	if table_check[2].to_i != 1
		STDERR.puts " [!] Could not find \"#{$options[:mysql_db]}.#{$options[:mysql_tbl]}\" in MySQL server, exiting..."
		STDERR.puts ""
		exit(1)
	else
		#check if table contains needed columns (id, date, time, ping, download, upload)
		column_check = `mysql --execute="SELECT column_name FROM information_schema.columns WHERE table_schema = \\\"#{$options[:mysql_db]}\\\" AND table_name = \\\"#{$options[:mysql_tbl]}\\\";"`
		column_check = Array(column_check.split(' '))		#separate each returned column name

		#needed columns in table
		mysql_col = ["id", "date", "time", "ping", "download", "upload"]

		if (mysql_col - column_check).empty? == false
			STDERR.puts " [!] \"#{$options[:mysql_db]}.#{$options[:mysql_tbl]}\" does not seem to contain the correct columns, exiting..."
			STDERR.puts ""
			exit(1)
		end
	end

	#check for speedtest-cli
	`which speedtest-cli`
	if $?.exitstatus != 0
		STDERR.puts " [!] Speedtest-cli not found, exiting..."
		STDERR.puts ""
		exit(1)
	end

	#check logfile
	if File.exists?($options[:logfile]) == false
		STDERR.puts " [!] Cannot find logfile: #{$options[:logfile]}, exiting..."
		STDERR.puts ""
		exit(1)
	elsif File.writable?($options[:logfile]) == false
		STDERR.puts " [!] Cannot write to logfile: #{$options[:logfile]}, exiting..."
		STDERR.puts ""
		exit(1)
	end
end

#conduct speed test
def speed_test
	#test command -- selects ping | download | upload
	test = `speedtest --server #{$options[:server]} --csv --csv-delimiter ";" | cut -d ";" -f 6,7,8`

	#separate results to assign to $results
	test = test.split(';')

	#typecast results to float and write to hash table
	$results[:ping] = test[0].to_f.round(2)							#round to two decimal places
	$results[:down] = (test[1].to_f / 1000000).round(2)				#bps to Mbps and round to two decimal places
	$results[:up] = (test[2].to_f / 1000000).round(2)				#bps to Mbps and round to two decimal places

	#get date and time, add to hash table
	#date -- YYYY-MM-DD
	$results[:date] = Time.now.strftime("%Y-%m-%d")
	#time -- HH:MM:SS
	$results[:time] = Time.now.strftime("%H:%M:%S")
end

#import speed test results to mysql database
def import
	#sql command
	add = `mysql --execute="INSERT INTO #{$options[:mysql_db]}.#{$options[:mysql_tbl]} (date,time,ping,download,upload) VALUES (\\\"#{$results[:date]}\\\",\\\"#{$results[:time]}\\\",#{$results[:ping]},#{$results[:down]},#{$results[:up]});"`

	#check if results successfully added to table?
end

#parse command-line arguments -- if no options are given, print help
ARGV << '-h' if ARGV.empty?

parser = OptionParser.new do |opts|
	opts.version = 'v1.0'
	opts.release = 'r1'
	opts.set_program_name('speedtest_daemon')
	opts.banner = "Usage: #{opts.program_name} [options]"
	opts.separator ""
	opts.on('-d', '--database [NAME]',	': Name of MySQL database storing results') do |op|
		$options[:mysql_db] = op
	end
	opts.on('-t', '--table [NAME]',	': Name of table in MySQL database storing results') do |op|
		$options[:mysql_tbl] = op
	end
	opts.on('-s', '--server [NUM]',	': Speedtest server ID',
									'	(Default: 6421)') do |op|
		$options[:server] = op
	end
	opts.on('-i', '--interval [NUM]',	': Time between each scan (in minutes)',
										'	(Default: 10 minutes)' do |op|
		$options[:interval] = (op.to_i * 60)									#convert from minutes to seconds for sleep()
	end
	opts.on('-l', '--logfile [PATH]',	': Name and path of logfile for daemon',
										'	(Default: "/var/log/speedtest.log")') do |op|
		$options[:logfile] = op
	end

	opts.on('-h', '--help', ': Prints this help dialogue and exits') do
		puts opts
		exit(0)
	end
	opts.on('-v', '--version', ': Prints version information and exits') do
		puts opts.ver()
		exit(0)
	end
	opts.separator ""
end
parser.parse!

####################################
##              MAIN              ##
####################################

error_check
STDERR.puts "#{Time.now} -- Network testing started..."					#write start time to log file

#speed_test
#import

STDERR.puts "#{Time.now} -- Network testing completed..."				#write end time to log file
exit(0)
