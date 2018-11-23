#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'

options = {
	:interval => 600,		#default interval is 10 minutes
	:mysql_tbl => "",
	:mysql_db => "",
	:server => 0,			#6421
	:logfile => "/var/log/speed_daemon/speed_daemon.log"
	:pidfile => "/var/run/speed_daemon/speed_daemon.pid"
}

parser = OptionParser.new do |opts|
	opts.version = 'v1.0'
	opts.release = 'r1'
	opts.set_program_name('Speed Daemon')
	opts.banner = "Usage: #{opts.program_name} [options]"
	opts.separator ""

	opts.on('-i', '--interval [NUM]', ': Time (in minutes) between each iteration of the daemon',
		'	(Default: 10 minutes)') do |op|
		options[:interval] = (op.to_i * 60)
	end
	opts.on('-d', '--database [NAME]', ': Name of MySQL database to use for storing results') do |op|
		options[:mysql_db] = op
	end
	opts.on('-t', '--table [NAME]', ': Name of table in MySQL database to use for storing results') do |op|
		options[mysql_tbl] = op
	end
	opts.on('-s', '--server [ID]', ': Server ID of Speedtest Server to use',
		'	(List available at !!!!!!!!!!!)') do |op|
		options[:server] = op
	end
	opts.on('--logfile [PATH/NAME]', ': File path and name for log file',
		'	(Default: /var/log/speed_daemon/speed_daemon.log)') do |op|
		options[:logfile] = op
	end
	opts.on('--pidfile [PATH/NAME]', ': File path and name for PID file',
		'	(Default: /var/run/speed_daemon/speed_daemon.pid)') do |op|
		options[:pidfile] = op
	end
	opts.on('--quit [PID FILE PATH/NAME]', ': Gracefully shutdown Speed Daemon, if running (REQUIRES PIDFILE)') do |op|
		if File.exists?(op)
			pid = File.read(op).to_i
			Process.kill(3,pid)
		else
			puts "Unable to locate PID file. Please kill the process manually."
		end
		exit(0)
	end
	opts.separator ""

	opts.on('-I', '--include [DIR]', ': Additional Ruby $LOAD_PATH directory, if required') do |op|
		$LOAD_PATH.unshift(*op.split(":").map{ |v| File.expand_path(v)})
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

require 'speed_daemon'

Daemon.new(options).run!
