#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'

options = {
	:mysql_tbl => "",
	:mysql_db => "",
	:interval => 600,		#default interval is 10 minutes
	:timeout => 300,		#timout is 5 minutes by default	
	:server => 0,
	:full_test => false,
	:dry_run => false,
	:quit => false,
	:logfile => "/var/log/speed_daemon/speed_daemon.log",
	:pidfile => "/var/run/speed_daemon/speed_daemon.pid"
}

#force '--help' option if no options are provided
ARGV << '-h' if ARGV.empty?

parser = OptionParser.new do |opts|
	opts.version = 'v1.1'
	opts.release = 'r1'
	opts.set_program_name('Speed Daemon')
	opts.banner = "Usage: #{$0} [options]"
	opts.separator "	Ex. #{$0} -d db_name -t tbl_name -s 6421 --interval 15 --timeout 10 -I ../lib"
	opts.separator ""

	opts.separator "Required Options:"
	opts.on('-d', '--database [NAME]', ': Name of MySQL database to use for storing results') do |op|
		options[:mysql_db] = op
	end
	opts.on('-t', '--table [NAME]', ': Name of table in MySQL database to use for storing results') do |op|
		options[:mysql_tbl] = op
	end
	opts.separator ""

	opts.separator "Additional Test Options:"
	opts.on('--interval [NUM]', ': Time (in minutes) between each iteration of the daemon',
		'	(Default: 10 minutes)') do |op|
		options[:interval] = (op.to_i * 60)
	end
	opts.on('--timeout [NUM]', ': Time (in minutes) to wait for test to complete before timing out',
		'	(Default: 5 minutes)') do |op|
		options[:timeout] = (op.to_i * 60)
	end
	opts.on('-s', '--server [ID]', ': Server ID of Speedtest Server to use',
		'	(List available at https://speedtestserver.com/)') do |op|
		options[:server] = op
	end
	opts.on('-f', '--full-test', ': Conduct three tests and log the average for every iteration',
		'	(Default: Run one test and log the results)') do
		options[:full_test] = true
	end
	opts.on('--dry-run', ': Test functionality of script without conducting a network test',
		'	(Runs daemon using pre-programmed values)') do
		options[:dry_run] = true
	end
	opts.on('--quit', ': Gracefully shutdown Speed Daemon, if running',
		'	(\'--pidfile\' option required if not using default path)') do
		options[:quit] = true
	end
	opts.separator ""

	opts.separator "Other Options:"
	opts.on('-I', '--include [DIR]', ': Additional Ruby $LOAD_PATH directory',
		'	(Relative path to the directory containing speed_daemon.rb, if not this one)') do |op|
		$LOAD_PATH.unshift(*op.split(":").map{ |v| File.expand_path(v)})
	end
	opts.on('--logfile [PATH/NAME]', ': File path and name for log file',
		'	(Default: /var/log/speed_daemon/speed_daemon.log)') do |op|
		options[:logfile] = op
	end
	opts.on('--pidfile [PATH/NAME]', ': File path and name for PID file',
		'	(Default: /var/run/speed_daemon/speed_daemon.pid)') do |op|
		options[:pidfile] = op
	end
	opts.on('-h', '--help', ': Print this help dialogue and exit') do
		puts opts
		exit(0)
	end
	opts.on('-v', '--version', ': Print version information and exit') do
		puts opts.ver()
		exit(0)
	end
end
parser.parse!

#check for required options
def opts_check(options)
	#check that required options were provided
	if options[:mysql_tbl].empty?
		abort("[!] MySQL table is a required option. Please check the command and try again.")
	end
	if options[:mysql_db].empty?
		abort("[!] MySQL database is a required option. Please check the command and try again.")
	end

	#check directories (log/pid), make if they don't exist
	if !File.directory?(File.dirname(options[:pidfile]))
		FileUtils.mkdir_p(File.dirname(options[:pidfile]), :mode => 0755)
		FileUtils.chown 'speed_daemon', 'root', File.dirname(options[:pidfile])
	end
	if !File.directory?(File.dirname(options[:logfile]))
		FileUtils.mkdir_p(File.dirname(options[:logfile]), :mode => 0755)
		FileUtils.chown 'speed_daemon', 'root', File.dirname(options[:logfile])
	end

	#only allow one test type (quick, full, dry)
	if options[:full_test] and options[:dry_run]
		abort("[!] Only one test type can be specified at a time. Please check options and try again.")
	end
end

def quit(pidfile)
	if File.exists?(pidfile)
		pid = File.read(pidfile).to_i
		Process.kill(3,pid)
		puts "[*] :QUIT signal sent. Daemon will exit on next iteration."
		exit(0)
	else
		abort("[!] Unable to locate PID file. Please kill the process manually.")
	end
end

#MAIN
#make sure script is being run as root
if Process.uid != 0
	abort("[!] This script must be run as root. Please elevate privileges and try again.")
end

#if '--quit' option specified, stop, otherwise start
if options[:quit]
	quit(options[:pidfile])
else
	#check script options
	opts_check(options)

	#load daemon code and run daemon
	begin
		retries ||= 0							#make retries counter
		require 'speed_daemon'					#attempt to load daemon code
	rescue LoadError => e
		#only retry once
		if retries == 0
			retries += 1

			#file not in $LOAD_PATH, load directory of speed_ctrl (in case they are in the same directory) and retry once
			$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__))) unless $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))
			retry
		else
			puts "[!] Unable to load 'speed_daemon.rb', please use '--include' option to specify directory."
			abort("#{e.class.name} -- #{e.message}")
		end
	end

	Daemon.new(options).run!
end
exit(0)
