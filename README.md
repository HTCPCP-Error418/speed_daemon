# speed_daemon

## About
This program is designed to utilize "speedtest-cli" to test a network connection every `x` minutes, logging the results to a MySQL database.
This can be helpful in ensuring you are getting the network speed you pay for, as well as troubleshooting intermittent connection issues.

## Files
 * speed_daemon.rb -- This is the actual daemon code that will conduct the tests and add the results to the database
   * This file will be located in `/usr/local/lib/`
 * speed_ctrl.rb -- This is the control script for daemon
   * This file will be located in `/usr/local/bin/`

## Initial Setup
`TODO`

## Setting up the MySQL Database
#### Creating the Database and Table
`TODO`

#### Setting up User Permissions
`TODO`
