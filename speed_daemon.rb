require 'fileutils'
require 'timeout'

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

		#set process name
#		puts "Setting process title..."								#DEBUG
		Process.setproctitle('speed_daemon')
#		puts "Process title set."									#DEBUG

		#change user from root to speed_daemon
#		puts "Changing process UID. Current UID: #{Process.uid}"	#DEBUG
		new_uid = Process::UID.from_name("speed_daemon")
		Process::UID.change_privilege(new_uid)
#		puts "New UID: #{Process.uid}"								#DEBUG
	end

	def run!
		STDOUT.puts "[*] Starting Speed Daemon..."
		check_pid
		daemonize
		write_pid
		trap_signals
		redirect_output
		log "[*] Speed Daemon started successfully."

		while !quit
			results = {
				:date => "",
				:time => "",
				:ping => 0,
				:down => 0,
				:up => 0
			}

			log "[*] Beginning connection test..."

			error_check
			begin
				Timeout::timeout(options[:timeout]) do
					full_test(results) if options[:full_test]
					dry_run(results) if options[:dry_run]
					quick_test(results) if !options[:full_test] and !options[:dry_run]
				end
			rescue Timeout::Error
				#if test times out, log all speeds as 0
				log "[!] Connection test timed out! Logging metrics as \"0\"..."
				results[:ping] = 0.00
				results[:down] = 0.00
				results[:up] = 0.00
				results[:date] = Time.now.strftime("%Y-%m-%d")
				results[:time] = Time.now.strftime("%H:%M:%S")
			end
			insert(results)

			log "[*] Connection test complete."

			sleep(options[:interval])
		end
#		STDOUT.puts "Speed Daemon stopped..."		#This echoes in the terminal poorly (since the process is detached) -- put back in if it can look better
	end

	def log(msg)
		STDERR.puts "[#{Process.pid}] [#{Time.now}] #{msg}"
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
			abort("[!] An instance is already running. Check #{options[:pidfile]} for Process ID")
		when :dead
			File.delete(options[:pidfile])
		end
	end

	def write_pid
		#check for directory
		if !File.directory?(File.dirname(options[:pidfile]))
			FileUtils.mkdir_p(File.dirname(options[:pidfile], :mode => 0755))
			FileUtils.chown 'speed_daemon', 'root', File.dirname(options[:pidfile])
		end
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
		rescue Errno::EACCES => e
			puts "[!] Unable to create PID file, exiting..."
			abort("#{e.class.name} -- #{e.message}")
		rescue Errno::ENOENT => e
			puts "[!] Unable to create PID file, exiting..."
			abort("#{e.class.name} -- #{e.message}")
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

	#redirect output to logfile, if logfile doesn't exist make it, if can't make it, error and exit
	def redirect_output
		#check for/create log directory
		if !File.directory?(File.dirname(options[:logfile]))
			FileUtils.mkdir_p(File.dirname(options[:logfile], :mode => 0755))
			FileUtils.chown 'speed_daemon', 'root', File.dirname(options[:logfile])
		end
		#check for/create log file
		if !File.exists?(options[:logfile])
			FileUtils.touch options[:logfile]
			FileUtils.chown 'speed_daemon', 'root', options[:logfile]
			File.chmod(0644, options[:logfile])
		end
		#check if log file is writable
		if !File.writable?(options[:logfile])
			abort("[!] Logfile does not appear to be writable, exiting...")
		else
			#file exists and is writable, redirect stderr
			$stderr.reopen(options[:logfile], 'a')
			$stderr.sync = true
		end
	#raise error if logfile cannot be created
	rescue Errno::EACCES => e
		puts "[!] Unable to create logfile, exiting..."
		abort("#{e.class.name} -- #{e.message}")
	end

	def error_check
		log "[*] Beginning error checks..."
		#double check that mysql db and tbl were provided
		log "	[-] Checking command line options."
		if (options[:mysql_db].empty? or options[:mysql_tbl].empty?)
			abort("[!] MySQL database and table names are required, exiting...")
		end

		#test if mysql is running
		log "	[-] Checking for running MySQL server."
		`systemctl status mysql > /dev/null`		#systemctl seems to have errors checking the status (sometimes) if this isn't run first...
		`systemctl is-active --quiet mysql`
		if $?.exitstatus != 0
			abort("[!] MySQL server does not appear to be running, exiting...")
		end

		#test if mysql database and table exist
		log "	[-] Checking for MySQL table."
		table_check = `mysql -u speed_daemon --execute="SELECT IF( EXISTS( SELECT * FROM information_schema.tables WHERE table_schema = \\\"#{options[:mysql_db]}\\\" AND table_name = \\\"#{options[:mysql_tbl]}\\\"), 1, 0);"`
		table_check = table_check.split(')')		#separate echoed query from sql server from query result (1 == table exists)
		if table_check[2].to_i != 1
			abort("[!] Could not find \"#{options[:mysql_db]}.#{options[:mysql_tbl]}\" in MySQL server, exiting...")
		else
			log "	[-] Checking for MySQL columns."
			#database and table exist, check for needed columns (id, date, time, ping, download, upload)
			column_check = `mysql -u speed_daemon --execute="SELECT column_name FROM information_schema.columns WHERE table_schema = \\\"#{options[:mysql_db]}\\\" AND table_name = \\\"#{options[:mysql_tbl]}\\\";"`
			column_check = Array(column_check.split(' '))

			#array to check against
			mysql_col = ["id", "date", "time", "ping", "download", "upload"]

			if !(mysql_col - column_check).empty?
				abort("[!] \"#{options[:mysql_db]}.#{options[:mysql_tbl]}\" does not appear to contain the correct columns, exiting...")
			end
		end

		#check for speedtest-cli
		log "	[-] Checking for speedtest-cli."
		`which speedtest-cli`
		if $?.exitstatus != 0
			abort("Speedtest-cli not found, exiting...")
		end
		log "[*] Error checks complete."
	end

	def quick_test(results)
		log "[*] Beginning quick connection test..."

		#test command -- selects ping | download | upload -- only use "--server" option if one was provided
		if options[:server] != 0	#server was specified
			test = `speedtest --server #{options[:server]} --csv --csv-delimiter ";" | cut -d ";" -f 6,7,8`
		else						#no server specified
			test = `speedtest --csv --csv-delimiter ";" | cut -d ";" -f 6,7,8`
		end
		log "	[-] Scan complete, adding results to hash table."

		#separate results to assign to results[]
		test = test.split(';')

		#typecast results and write to hash table
		results[:ping] = test[0].to_f.round(2)					#round to two decimal places
		results[:down] = (test[1].to_f / 1000000).round(2)		#bps to Mbps and round to two decimal places
		results[:up] = (test[2].to_f / 1000000).round(2)		#bps to Mbps and round to two decimal places

		#get date and time, write to hash table
		#date -- YYYY-MM-DD
		results[:date] = Time.now.strftime("%Y-%m-%d")
		#time -- HH:MM:SS
		results[:time] = Time.now.strftime("%H:%M:%S")
		log "[*] Quick connection test complete."
	end

	#if you are reading this, please help... there has to be a way to do this that doesn't make me gag...
	def full_test(results)
		log "[*] Beginning full connection test..."
		if options[:server] != 0
			test = "speedtest --server #{options[:server]} --csv --csv-delimiter \";\" | cut -d \";\" -f 6,7,8"
		else
			test = 'speedtest --csv --csv-delimiter ";" | cut -d ";" -f 6,7,8'
		end

		#create variable to hold results of each test
		test0 = ""
		test1 = ""
		test2 = ""

		#do three tests and average the results
		counter = 0
		while counter < 3
			log "	[-] Conducting scan: #{(counter + 1)}"
			speed_results = `#{test}`

			#gross...
			if counter == 0
				test0 = "#{speed_results}".split(";")
			elsif counter == 1
				test1 = "#{speed_results}".split(";")
			elsif counter == 2
				test2 = "#{speed_results}".split(";")
			end

			#average results and write to hash table
			results[:ping] = ((test0[0].to_f + test1[0].to_f + test2[0].to_f) / 3).round(2)					#average results of three tests, round to two decimal places
			results[:down] = (((test0[1].to_f + test1[1].to_f + test2[1].to_f) / 3) / 1000000).round(2)		#average results of three tests, bps to Mbps, round to two decimal places
			results[:up] = (((test0[2].to_f + test1[2].to_f + test2[2].to_f) / 3) / 1000000).round(2)		#average results of three tests, bps to Mbps, round to two decimal places
		end

		log "	[-] Scans complete, adding results to hash table."
		#get date and time, write to hash table
		#date -- YYY-MM-DD
		results[:date] = Time.now.strftime("%Y-%M-%D")
		#time -- HH:MM:SS
		results[:time] = Time.now.strftime("%H:%M:%S")
		log "[*] Full connection test complete."
	end

	def dry_run(results)
		log "[*] Beginning dry run..."
		if options[:server] != 0
			log "	[-] Command: speedtest --server #{options[:server]} --csv --csv-delimiter \";\" | cut -d \";\" -f 6,7,8"
		else
			log "	[-] Command: speedtest --csv --csv-delimiter \";\" | cut -d \";\" -f 6,7,8"
		end

		test = ["5.5555", "55555555", "55555555"]
		log "	[-] Test values: #{test}"

		results[:ping] = test[0].to_f.round(2)
		results[:down] = (test[1].to_f / 1000000).round(2)
		results[:up] = (test[2].to_f / 1000000).round(2)

		results[:date] = Time.now.strftime("%Y-%m-%d")
		results[:time] = Time.now.strftime("%H:%M:%S")

		log "	[-] Results values: #{results}"
		log "[*] Dry run complete."
	end

	#insert results into database
	def insert(results)
		log "[*] Adding results to MySQL database..."
		`mysql -u speed_daemon --execute="INSERT INTO #{options[:mysql_db]}.#{options[:mysql_tbl]} (date,time,ping,download,upload) VALUES (\\\"#{results[:date]}\\\",\\\"#{results[:time]}\\\",#{results[:ping]},#{results[:down]},#{results[:up]});"`	

		#log, print to stdout, and exit if not added to database correctly
		if $?.exitstatus != 0
			log "	[!] Error adding results to \"#{options[:mysql_db]}.#{options[:mysql_tbl]}\""
			abort("[!] Error adding results to \"#{options[:mysql_db]}.#{options[:mysql_tbl]}\", exiting...")
		end
		log "[*] Results added to MySQL database."
	end
end
