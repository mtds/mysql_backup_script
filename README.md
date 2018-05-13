# Wrapper script over Percona xtrabackup

The main purpose of this shell script is to provide a wrapper over the [Xtrabacup tool from Percona](https://www.percona.com/software/mysql-database/percona-xtrabackupa). It provides an easy way to have a full and incremental backups from a MySQL instance.

It was mainly tested on **Debian based** Linux distributions. 

Scipts provided:
* ``innobackupex-runner.sh``:  full/incremental MySQL backups.
* ``innobackupex-restore.sh``: restore script (Note: it is intended to be executed __interactively__).

## How it works

``innobackupex-runner.sh`` can read a configuration file in INI format (see example under the ``etc`` subdirectory of this repo or it can be used interactively through multiple command line options. *Note* that this script has to be executed with __root__ privileges.

If a configuration file is present, the only mandatory option on the command line is ``-d`` which is used to specify where is the directory to store the backup files.

In the configuration file the two most important entries are ``mycnf`` (which points to a MySQL configuration file, e.g. under ``/etc/mysql/my.cnf``) and ``cnfauth`` which points to configuration file which contains the username and password used to connect to a MySQL instance. In the example used in this repo, it points to ``/etc/mysql/debian.cnf`` which contains the credentials of special user defined on default installation of MySQL under Debian. Of course, it is always possible to define your own config files.

## Command Line Options

The following is a complete list of the cmd line options for the backup script:
* ``-d``  Directory used to store database backup 
* ``-a``  Path of a CNF file containing admin credentials 
* ``-f``  Path to my.cnf database config file 
* ``-g``  Group to read from the config file 
* ``-u``  Username used when connecting to the database 
* ``-p``  Password used when connecting to the database 
* ``-i``  Username/Password will be provided on the cmd line 
* ``-H``  Host used when connecting to the database 
* ``-P``  Port number used when connecting to the database 
* ``-S``  Socket used when connecting to the database 
* ``-v``  Verbose mode: print more output messages 
* ``-h``  Display basic help

## Origin of this script

This script is originally derived from the one available through this [Github gist](https://gist.github.com/bleleve/5605430#file-innobackupex-runner-sh).

I have made by myself the following modifications:

* Default shell changed to /bin/bash.
* Renamed some variables.
* All the external commands are invoked with the full path.
* Splitted the script logic in multiple functions.

Plus the following enhancements were not present in the original version:

* Parameters can be read from a config file (through an INI parser).
* Check if there's enough free disk space before starting the backup.
* Logging: when the script is not used interactively all the output/error messages are logged into a file.

The copyright of the original developers is reported here and also on the script itself:

* (C)2010 Owen Carter @ Mirabeau BV
* (C)2013 Benoit LELEVE' @ Exsellium (www.exsellium.com)

In order to read an INI configuration file, this repository is also including the extremely useful ``INI Parser`` from Ruediger Meier, which is available through this [Github repo](https://github.com/rudimeier/bash_ini_parser).

## Define a CRON entry

Run the script every four hours after defining an entry under ``/etc/cron.d``:
```
#
# Make MySQL backups (full/incremental) every four hours:
#
0 */4 * * * root /usr/bin/innobackupex-runner.sh -d /opt/db_backups
```

