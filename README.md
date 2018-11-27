# speed_daemon

## About
Speed Daemon is a daemon designed to test the speed of a connection every `x` minutes and log the results in
a MySQL database.

This is useful for tracking the average connection speed for a network or tracking intermittent connection
issues.

## Usage and Options
```
Usage: ./speed_ctrl.rb [options]
	Ex. ./speed_ctrl.rb -d db_name -t tbl_name -s 6421 --interval 15 --timeout 10 -I.

Required Options:
    -d, --database [NAME]            : Name of MySQL database to use for storing results
    -t, --table [NAME]               : Name of table in MySQL database to use for storing results

Additional Test Options:
        --interval [NUM]             : Time (in minutes) between each iteration of the daemon
                                     	(Default: 10 minutes)
        --timeout [NUM]              : Time (in minutes) to wait for test to complete before timing out
                                     	(Default: 5 minutes)
    -s, --server [ID]                : Server ID of Speedtest Server to use
                                     	(List available at https://speedtestserver.com/)
    -f, --full                       : Conduct three tests and log the average for every iteration
                                     	(Default: Run one test and log the results)

Other Options:
        --quit [PID FILE PATH/NAME] || [PID]
                                     : Gracefully shutdown Speed Daemon, if running (REQUIRES PIDFILE OR PID)
    -I, --include [DIR]              : Additional Ruby $LOAD_PATH directory, if required
                                     	(This will be the directory containing speed_daemon.rb)
        --logfile [PATH/NAME]        : File path and name for log file
                                     	(Default: /var/log/speed_daemon/speed_daemon.log)
        --pidfile [PATH/NAME]        : File path and name for PID file
                                     	(Default: /var/run/speed_daemon/speed_daemon.pid)
    -h, --help                       : Print this help dialogue and exit
    -v, --version                    : Print version information and exit
```

## Files
```
	/
	|-- /var/
	|	|-- /log/
	|	|	|-- /speed_daemon/
	|	|		|-- speed_daemon.log
	|	|-- /run/
	|	|	|-- /speed_daemon/
	|	|	|	|-- speed_daemon.pid
	|
	|-- /etc/
	|	|-- /logrotate.d/
	|	|	|-- speed_daemon
	|
	|-- /usr/
	|	|-- /local/
	|	|	|-- /lib/
	|	|	|	|-- speed_daemon.rb
	|	|	|-- /bin/
	|	|	|	|-- speed_ctrl.rb
```
| File                | Description                                             |
| :-----------------: | :------------------------------------------------------ |
| `speed_daemon.log`  | The default log file for the daemon                     |
| `speed_daemon.pid`  | The PID/lock file for the daemon                        |
| `speed_daemon`      | Optional file used to setup log rotation for the daemon |
| `speed_daemon.rb`   | The main code and functions for the daemon              |
| `speed_ctrl.rb`     | The control script for the daemon (requires root)       |

The `--include` option was added to the control script for this daemon, allowing the two main files to
be placed in any directory/directories.

---

## Initial Setup
#### Required software: (All installed from `apt`)
* Ruby (I have 2.3.3; I tried to keep it compatible with 1.9.0, but haven't tested)
* speedtest-cli
* MySQL (Or derivative; I used MariaDB)

#### Service Account
This script utilizes a service account named `speed_daemon` to avoid needing to run as root. This account can
be created with the following command:
```bash
	root$ useradd -r -s /usr/bin/nologin/ speed_daemon
```
#### Logrotate
This an optional file that will setup automatic log rotation for the log files. The values listed in the
example below are not required and can be customized. See [here](https://manpages.debian.org/jessie/logrotate/logrotate.8.en.html)
for details.
```bash
	/var/log/speed_daemon/speed_daemon.log {
		rotate 8
		weekly
		compress
		missingok
		notifempty
	}
```

---

## Setting up the MySQL Database
After installing a MySQL DBMS, the database and table for the daemon must be created, and the user permissions
must be setup to allow password-less login for the daemon.

The database and table can be named whatever you would like, since they are passed as options to the daemon.
The database can be created using the following command:
```bash
	root$ mysqladmin -u root -p create [DB_NAME]
```
After the database has been created, log in to MySQL and create the table:
```
	> USE [DB_NAME];
	> CREATE TABLE [TABLE_NAME] (
		-> id INT NOT NULL AUTO_INCREMENT,
		-> date DATE NOT NULL,
		-> time TIME NOT NULL,
		-> ping FLOAT NOT NULL,
		-> download FLOAT NOT NULL,
		-> upload FLOAT NOT NULL,
		-> PRIMARY KEY( id )
		-> );
```
Now the user permissions can be setup. To avoid needing to hard-code a password, I utilized the `unix_socket`
plugin. If this plugin isn't included with the MySQL installation by default, it can be added with the following
command:
```
	> INSTALL PLUGIN unix_socket SONAME 'auth_socket';
	> GRANT SELECT,INSERT ON [DB_NAME].[TABLE_NAME] TO 'speed_daemon'@'localhost' IDENTIFIED VIA unix_socket;
```
Now, the `speed_daemon` service account should have select and insert permissions on the database without
needing to provide a password and the initial setup should be complete.
