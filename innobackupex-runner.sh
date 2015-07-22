#!/bin/bash
# 
# Script to create full and incremental backups (for all databases on server) using innobackupex from Percona.
# http://www.percona.com/doc/percona-xtrabackup/innobackupex/innobackupex_script.html
#
# Every time it runs will generate an incremental backup except for the first time (full backup).
# FULLBACKUPLIFE variable will define your full backups schedule.
#
# NOTE
# ----
# This script is derived from: https://gist.github.com/bleleve/5605430#file-innobackupex-runner-sh
#
# (C)2015 Matteo Dessalvi @ GSI (HPC)
#
# => Modifications:
#    - Default shell changed to /bin/bash.
#    - Renamed some variables.
#    - All the external commands are invoked with the full path.
#    - Splitted the script in multiple functions.
#
# => Enhancements:
#    - Parameters can be read from a config file (added a special INI parser).
#    - Logging: when the script is not used interactively all the output/error 
#      messages are logged into a file.
#
# ------------------------------------------------------------------------------------------
#
# (C)2010 Owen Carter @ Mirabeau BV
# This script is provided as-is; no liability can be accepted for use.
# You are free to modify and reproduce so long as this attribution is preserved.
#
# (C)2013 Benoit LELEVE' @ Exsellium (www.exsellium.com)
# Adding parameters in order to execute the script in a multiple MySQL instances environment
#

SCRIPTNAME=$(basename "$0")
INTERACTIVE=false # used only when credentials are provided on the command line
CNFSCRIPT=/opt/scripts/mysql_backup/etc/runner.conf

##################################
# Display usage message and exit #
##################################
usage() {
  cat <<EOF
  Usage: $SCRIPTNAME -d backdir [-f config.cnf] [-g group] [-a auth.cnf] | -i -u username [-p password] [-H host] [-P port] [-S socket] [-v] | [-h]
  -d  Directory used to store database backup
  -f  Path to my.cnf database config file
  -g  Group to read from the config file
  -u  Username used when connecting to the database
  -p  Password used when connecting to the database
  -H  Host used when connecting to the database
  -P  Port number used when connecting to the database
  -S  Socket used when connecting to the database
  -i  Username/Password will be provided on the cmd line
  -a  Path of a CNF file containing admin credentials
  -v  Verbose mode: print more output messages
  -h  Display basic help
EOF
  exit 0
}


# Display a message or redirect it to the log file:
log_msg () {
  if [ "$VERBOSE" = true ] ; then
    echo "$1"
  else
    echo `/bin/date +%b' '%d' '%H:%m:%S` "$1" >> $LOGFILE
  fi
}


# Extract MySQL credentials (user/password) from a CNF file:
read_credentials () {
  # Source the parser:
  local DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  source $DIR/read_ini.sh

  # Call the parser function over the MySQL cnf file:
  read_ini -p mysqlCnf $CNFAUTH

  # Concatenate the parameters for innobackupex:
  USEROPTIONS="--user=$mysqlCnf__client__user --password=$mysqlCnf__client__password"
}


# Extract the options from the configuration file:
read_config () {
  # Source the parser:
  local DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  source $DIR/read_ini.sh

  # Call the parser function over the MySQL cnf file:
  read_ini -p scriptCnf $CNFSCRIPT

  # Script options:
  INNOBACKUPEXBINCMD="$scriptCnf__config__innobackupexbincmd"
  TMPFILE="$scriptCnf__config__tmpfile"
  LOGFILE="$scriptCnf__config__logfile"

  # MySQL configs and binaries:
  MYSQL="$scriptCnf__config__mysql"
  MYCNF="$scriptCnf__config__mycnf"
  CNFAUTH="$scriptCnf__config__cnfauth"
  MYSQLADMIN="$scriptCnf__config__mysqladmin"

  # Backup configs:
  FULLBACKUPLIFE="$scriptCnf__config__fullbackuplife"
  KEEP="$scriptCnf__config__keep"
}


# Check if the option arguments provided are correct:
check_options() {

  # Verify if the backup directory is provided/available/writable:
  if [ -z "$BACKUPDIR" ]; then
    log_msg "ERROR: Backup directory is required. For help, type: $SCRIPTNAME -h."
    exit 1
  fi

  if [ ! -d $BACKUPDIR ]; then
    log_msg "ERROR: Backup destination folder $BACKUPDIR does not exist."
    exit 1
  fi

  if [ ! -w "$BACKUPDIR" ]; then
    log_msg "ERROR: $BACKUPDIR is not writable by the UID used to launch the script."
    exit 1
  fi

  # Used by innonackupex: this option accepts a string argument that specifies the 
  # group which should be read from the configuration file. This is needed if you 
  # use mysqld_multi. This can also be used to indicate groups other than mysqld 
  # and xtrabackup.
  if [ ! -z "$MYGROUP" ]; then DEFGROUP="--defaults-group=$MYGROUP"; fi

  # If username and password are provided with the '-u' and '-p' options on the cmd line:
  if [ "$INTERACTIVE" = true ]; then
     if [ -z "$MYUSER"]; then
       log_msg "Database username is required. For help, type: $SCRIPTNAME -h"
       exit 1
     else
       # Concatenate parameters into innobackupex ones:
       USEROPTIONS="--user=$MYUSER"
       if [ ! -z "$MYPASSWD" ]; then USEROPTIONS="$USEROPTIONS --password=$MYPASSWD"; fi
     fi
   else
    read_credentials # We'll get MySQL credentials from a CNF file.
  fi

  # Connection parameters: if none of the following are provided the script we'll use
  # the ones that comes from /etc/mysql/my.cnf.
  if [ ! -z "$MYHOST" ]; then USEROPTIONS="$USEROPTIONS --host=$MYHOST"; fi
  if [ ! -z "$MYPORT" ]; then USEROPTIONS="$USEROPTIONS --port=$MYPORT"; fi
  if [ ! -z "$MYSOCKET" ]; then USEROPTIONS="$USEROPTIONS --socket=$MYSOCKET"; fi
}


# Execute the backup procedure:
do_backup() {

  # Grab start time
  local STARTED_AT=`/bin/date +%s`

  # Full and incremental backups directories
  local FULLBACKUPDIR=$BACKUPDIR/full
  local INCRBACKUPDIR=$BACKUPDIR/incr
  
  # Check options before proceeding
  if [ ! -x $INNOBACKUPEXBINCMD ]; then
    log_msg "$INNOBACKUPEXBINCMD does not exist."
    exit 1
  fi
  
  if [ -z "`$MYSQLADMIN $USEROPTIONS status | /bin/grep 'Uptime'`" ] ; then
    log_msg "HALTED: MySQL does not appear to be running."
    exit 1
  fi
  
  if ! `echo 'exit' | $MYSQL -s $USEROPTIONS` ; then
    log_msg "HALTED: Supplied mysql username or password appears to be incorrect (not copied here for security, see script)."
    exit 1
  fi

  if [ "$VERBOSE" = true ] ; then
    # Some info output
    echo "----------------------------"
    echo
    echo "$SCRIPTNAME: MySQL backup script"
    echo "started: `/bin/date`"
    echo
  else
    log_msg "$SCRIPTNAME: backup started"
  fi
  
  # Create full and incr backup directories if they not exist.
  /bin/mkdir -p $FULLBACKUPDIR
  /bin/mkdir -p $INCRBACKUPDIR
  
  # Find latest full backup:
  LATEST_FULL=`/usr/bin/find $FULLBACKUPDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | /usr/bin/sort -nr | /usr/bin/head -1`
  
  # Get last modification time of the latest backup:
  LATEST_FULL_CREATED_AT=`/usr/bin/stat -c %Y $FULLBACKUPDIR/$LATEST_FULL`
  
  # Run an incremental backup if latest full is still valid. Otherwise, run a new full one.
  if [ "$LATEST_FULL" -a `expr $LATEST_FULL_CREATED_AT + $FULLBACKUPLIFE + 5` -ge $STARTED_AT ] ; then
    # Create incremental backups dir if not exists.
    TMPINCRDIR=$INCRBACKUPDIR/$LATEST_FULL
    /bin/mkdir -p $TMPINCRDIR
    
    # Find latest incremental backup.
    LATEST_INCR=`/usr/bin/find $TMPINCRDIR -mindepth 1 -maxdepth 1 -type d | /usr/bin/sort -nr | /usr/bin/head -1`
    
    # If this is the first incremental, use the full as base. Otherwise, use the latest incremental as base.
    if [ ! $LATEST_INCR ] ; then
      INCRBASEDIR=$FULLBACKUPDIR/$LATEST_FULL
    else
      INCRBASEDIR=$LATEST_INCR
    fi
    
    log_msg "Running new incremental backup using $INCRBASEDIR as base."
    $INNOBACKUPEXBINCMD --defaults-file=$MYCNF $DEFGROUP $USEROPTIONS --incremental $TMPINCRDIR --incremental-basedir $INCRBASEDIR > $TMPFILE 2>&1
  else
    log_msg "Running new full backup."
    $INNOBACKUPEXBINCMD --defaults-file=$MYCNF $DEFGROUP $USEROPTIONS $FULLBACKUPDIR > $TMPFILE 2>&1
  fi
  
  if [ -z "`/usr/bin/tail -1 $TMPFILE | /bin/grep 'completed OK!'`" ] ; then
    if [ "$VERBOSE" = true ] ; then
      echo "$INNOBACKUPEXBINCMD failed:"; echo
      echo "---------- ERROR OUTPUT from $INNOBACKUPEXBINCMD ----------"
      /bin/cat $TMPFILE
      /bin/rm -f $TMPFILE
    else
      log_msg "ERROR: the backup procedure has failed. More details on: $TMPFILE"
    fi
    exit 1
  fi
  
  local THISBACKUP=`/usr/bin/awk -- "/Backup created in directory/ { split( \\\$0, p, \"'\" ) ; print p[2] }" $TMPFILE`
  /bin/rm -f $TMPFILE
  
  log_msg "Databases backed up successfully to: $THISBACKUP"
  
  # Cleanup
  log_msg "Cleanup. Keeping only $KEEP full backups and its incrementals."
  
  local AGE=$(($FULLBACKUPLIFE * $KEEP / 60))

  # Add the 'echo' only if VERBOSE is true:
  /usr/bin/find $FULLBACKUPDIR -maxdepth 1 -type d -mmin +$AGE -execdir echo "removing: "$FULLBACKUPDIR/{} \; -execdir rm -rf $FULLBACKUPDIR/{} \; -execdir echo "removing: "$INCRBACKUPDIR/{} \; -execdir rm -rf $INCRBACKUPDIR/{} \;
  
  log_msg "Backup completed."
}

#
# Main
#

# Run the backup script as ROOT:
if [ "$EUID" -ne 0 ]; then 
  echo "Please run $SCRIPTNAME as root."
  exit 1
fi

# Read the configuration parameters from the config file.
read_config

# Parse cmd line parameters:
while getopts ":d:f:g:a:u:p:H:P:S:ivh" opt; do
  case $opt in
    d )  BACKUPDIR=$OPTARG ;;
    f )  MYCNF=$OPTARG ;;
    g )  MYGROUP=$OPTARG ;;
    u )  MYUSER=$OPTARG ;;
    p )  MYPASSWD=$OPTARG ;;
    H )  MYHOST=$OPTARG ;;
    P )  MYPORT=$OPTARG ;;
    S )  MYSOCKET=$OPTARG ;;
    i )  INTERACTIVE=true ;;
    a )  CNFAUTH=$OPTARG ;;
    v )  VERBOSE=true ;;
    h )  usage ;;
    \?)  echo "Invalid option: -$OPTARG"
         echo "For help, type: $SCRIPTNAME -h"
         exit 1 ;;
    : )  echo "Option -$OPTARG requires an argument"
         echo "For help, type: $SCRIPTNAME -h"
         exit 1 ;;
  esac
done

# Verify the options passed through the command line.
check_options

# Execute the backup procedure.
do_backup

exit 0
