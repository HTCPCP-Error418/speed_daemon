require 'fileutils'

class Daemon

	def self.run!(options)
		Daemon.new(options).run!
	end

	attr_reader :options, :quit

	def initialize(options)
		@options = options

		#expand paths for logfile, pidfile
		options[:logfile] = File.expand_path(options[:logfile])
		options[:pidfile] = File.expand_path(options[:pidfile])
	end

	def run!
		STDOUT.puts "Starting Speed Daemon..."
		check_pid
		daemonize
		write_pid
		trap_signals
		redirect_output

		while !quit
			results = {
				:date => "",
				:time => "",
				:ping => 0,
				:down => 0,
				:up => 0
			}

			log "Beginning connection test..."

			#work

			log "Connection test complete."

			sleep(options[:interval])
		end
		STDOUT.puts "Stopping Speed Daemon..."
	end

	def log(msg)
		puts "[#{Process.pid}] [#{Time.now}] #{msg}"
	end

	def pid_status(pidfile)
		return :exited unless File.exists?(pidfile)
		pid = File.read(pidfile).to_i
		return :dead if pid == 0
		Process.kill(0, pid)
		:running
	rescue Errno::ESRCH
		:dead
	rescue Errno::EPERM
		:not_owned
	end

	def check_pid
		case pid_status(options[:pidfile])
		when :running, :not_owned
			puts "An instance is already running. Check #{options[:pidfile]}"
			exit(1)
		when :dead
			File.delete(options[:pidfile])
		end
	end

	def write_pid
		begin
			File.open(options[:pidfile], ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f|
				f.write("#{Process.pid}")
			}
			at_exit {
				File.delete(options[:pidfile]) if File.exists?(options[:pidfile])
			}
		rescue Errno::EEXIST
			check_pid
			retry
		end
	end

	def trap_signals
		trap(:QUIT) do
			@quit = true
		end
	end

	def daemonize
		exit if fork
		Process.setsid
		exit if fork
		Dir.chdir "/"
	end

	def redirect_output
		if !File.directory?(File.dirname(options[:logfile]))
			FileUtils.mkdir_p(File.dirname(options[:logfile], :mode => 0755))
		end
		if !File.exists?(options[:logfile])
			FileUtils.touch options[:logfile]
			File.chmod(0644, options[:logfile])
		end
		$stderr.reopen(options[:logfile], 'a')
		$stderr.sync = true
	end

	#error_check
	#speed_test
	#import
	

end
