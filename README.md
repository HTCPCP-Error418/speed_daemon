# Speed Daemon
* [About](#about)
* [Usage and Options](#usage-and-options)
* [Default Files and File Paths](#default-files-and-file-paths)
* [System Configuration](#system-configuration)
	* [Required Software](#required-software)
	* [Service Account Creation](#service-account-creation)
	* [Logrotate Configuration](#logrotate-configuration)
* [Setting up the MySQL Database](#setting-up-the-mysql-database)

## About
Speed Daemon is a daemon designed to test the speed of a connection every `x` minutes and log the results in
a MySQL database. This is useful for tracking the average connection speed for a network or tracking
intermittent connection issues. It was originally created to document network outages and below-advertised
speeds from an ISP (and to learn how daemons work).

If you experience any issues with this daemon; have feature requests; or know have suggestions on better ways
to accomplish some functions, please let me know.

## Usage and Options
```
Usage: ./speed_ctrl.rb [options]
	Ex. ./speed_ctrl.rb -d db_name -t tbl_name -s 6421 --interval 15 --timeout 10 -I../lib

Required Options:
    -d, --database [NAME]            : Name of MySQL database to use for storing results
    -t, --table [NAME]               : Name of table in MySQL database to use for storing results
    -I, --include [DIR]              : Additional Ruby $LOAD_PATH directory
                                     	(Relative path to the directory containing speed_daemon.rb)

Additional Test Options:
        --interval [NUM]             : Time (in minutes) between each iteration of the daemon
                                     	(Default: 10 minutes)
        --timeout [NUM]              : Time (in minutes) to wait for test to complete before timing out
                                     	(Default: 5 minutes)
    -s, --server [ID]                : Server ID of Speedtest Server to use
                                     	(List available at https://speedtestserver.com/)
    -f, --full-test                  : Conduct three tests and log the average for every iteration
                                     	(Default: Run one test and log the results)
        --dry-run                    : Test functionality of script without conducting a network test
                                     	(Runs daemon using pre-programmed values)
        --quit                       : Gracefully shutdown Speed Daemon, if running
                                     	('--pidfile' option required if not using default path)

Other Options:
        --logfile [PATH/NAME]        : File path and name for log file
                                     	(Default: /var/log/speed_daemon/speed_daemon.log)
        --pidfile [PATH/NAME]        : File path and name for PID file
                                     	(Default: /var/run/speed_daemon/speed_daemon.pid)
    -h, --help                       : Print this help dialogue and exit
    -v, --version                    : Print version information and exit
```

## Default Files and File Paths
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

The `--logfile` and `--pidfile` options were added to allow the user to change these directories; however,
the daemon has not been tested using different file paths. Additionally, the `--include` option was added to
the control script for this daemon, allowing the two main files to be placed in any directory/directories;
however, this has resulted in always requiring this option.

---

## System Configuration
#### Required Software:
* Ruby (Should be 1.9.0+; only tested with 2.3.3)
* speedtest-cli
* MySQL (Or derivative; tested on MariaDB)

```bash
apt install ruby speedtest-cli mysql-server -y
```

#### Service Account Creation
This script utilizes a service account named `speed_daemon` to avoid needing to run as root. This account can
be created with the following command:
```bash
root$ useradd -r speed_daemon
```
#### Logrotate Configuration
This an optional file that will setup automatic log rotation for the log files. The values listed in the
example below are not required and can be customized. See
[here](https://manpages.debian.org/jessie/logrotate/logrotate.8.en.html) for details.

```
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
After installing a MySQL DBMS, the database, table, and user account must be set up to allow the daemon to
add the results to the database. The database and table names can be customized, as they are required options
when starting the daemon. Previous versions of this daemon attempted to utilize 'auth_socket' to avoid the
need to store a password in the script or a config file; however, this method resulted in issues when switching
the Process ID to the service account. The method below creates a user without a password and grants only
insert and select permissions to reduce the attack surface.

The commands below cover the process of configuring the MySQL DBMS:

```bash
root$ mysql
```
```
MariaDB [(none)]> CREATE DATABASE [db_name];
MariaDB [(none)]> CREATE TABLE [db_name].[tbl_name] (
	-> id INT NOT NULL AUTO_INCREMENT,
	-> date DATE NOT NULL,
	-> time TIME NOT NULL,
	-> ping FLOAT NOT NULL,
	-> download FLOAT NOT NULL,
	-> upload FLOAT NOT NULL,
	-> PRIMARY KEY ( id )
	-> );
MariaDB [(none)]> CREATE USER 'speed_daemon'@'localhost';
MariaDB [(none)]> GRANT INSERT,SELECT ON [db_name].[tbl_name] TO 'speed_daemon'@'localhost';
```

---

The system should now be configured. The '--dry-run' option can be used to test the script; however, it should
be noted that this will insert pre-programmed values into the table, which should be deleted prior to beginning
to collect data to ensure that the results are not skewed.
