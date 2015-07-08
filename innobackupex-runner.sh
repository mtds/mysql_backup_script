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
# => Modifications:
# - Default shell changed to /bin/bash.
# - Renamed some variables
# - All the external commands are invoked with the full path.
#
# => Enhancements:
# - Reading username/password from an external file.
# - Added a verbose mode: when the script is not used 
#   interactively all the output/error messages are
#   logged into a file.
#
# ------------------------------------------------------------------------------------------
#
# (C)2010 Owen Carter @ Mirabeau BV
# This script is provided as-is; no liability can be accepted for use.
# You are free to modify and reproduce so long as this attribution is preserved.
#
# (C)2013 Benoît LELEVÉ @ Exsellium (www.exsellium.com)
# Adding parameters in order to execute the script in a multiple MySQL instances environment
#

INNOBACKUPEXBIN=innobackupex
INNOBACKUPEXBINCMD=/usr/bin/$INNOBACKUPEXBIN
TMPFILE="/tmp/innobackupex-runner.$$.tmp"
MYSQL=/usr/bin/mysql
MYSQLADMIN=/usr/bin/mysqladmin
FULLBACKUPLIFE=604800 # Lifetime of the latest full backup in seconds
KEEP=1 # Number of full backups (and its incrementals) to keep
SCRIPTNAME=$(basename "$0")
LOGFILE=/var/log/innobackup.log

# Grab start time
STARTED_AT=`/bin/date +%s`

##################################
# Display usage message and exit #
##################################
usage() {
  cat <<EOF
Usage: $SCRIPTNAME [-d backdir] [-f config] [-g group] [-e] [-a /path/auth.cnf] | ([-u username] [-p password]) [-H host] [-P port] [-S socket] [-v]
  -d  Directory used to store database backup
  -f  Path to my.cnf database config file
  -g  Group to read from the config file
  -u  Username used when connecting to the database
  -p  Password used when connecting to the database
  -H  Host used when connecting to the database
  -P  Port number used when connecting to the database
  -S  Socket used when connecting to the database
  -e  Use an external config files for the credentials
  -a  Path of a CNF file with admin credentials (by default /etc/mysql/debian.cnf is used)
  -v  Verbose mode: print more output messages
  -h  Display basic help
EOF
  exit 0
}


# Parse parameters
while getopts ":d:f:g:a:u:p:H:P:S:evh" opt; do
  case $opt in
    d )  BACKUPDIR=$OPTARG ;;
    f )  MYCNF=$OPTARG ;;
    g )  MYGROUP=$OPTARG ;;
    u )  MYUSER=$OPTARG ;;
    p )  MYPASSWD=$OPTARG ;;
    H )  MYHOST=$OPTARG ;;
    P )  MYPORT=$OPTARG ;;
    S )  MYSOCKET=$OPTARG ;;
    e )  EXTCNF=true ;;
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

# Display a message or redirect it to the log file:
log_msg () {
  if [ "$VERBOSE" = true ] ; then
    echo "$1"
  else
    echo `/bin/date +%b' '%d' '%H:%m:%S` "$1" >> $LOGFILE
  fi
}

# Check required parameters
if [ -z "$BACKUPDIR" ]; then
  log_msg "Backup directory is required. For help, type: $SCRIPTNAME -h"
  exit 1
fi

if [ -z "$MYUSER" ] && [ -z "$EXTCNF" ]; then
  log_msg "Database username is required. For help, type: $SCRIPTNAME -h"
  exit 1
fi

if [ -z "$MYCNF" ]; then MYCNF=/etc/mysql/my.cnf; fi
if [ ! -z "$MYGROUP" ]; then DEFGROUP="--defaults-group=$MYGROUP"; fi

if [ "$EXTCNF" = true ] ; then

#
# CHECK ME:
#
#	- Scripts installation directory
#

  # Source the parser:
  . /opt/scripts/read_ini.sh

  # By default we'll use the Debian sys maintainer user for the backup operations:
  if [ -z "$CNFAUTH" ]; then CNFAUTH=/etc/mysql/debian.cnf; fi

  # Call the parser function over the MySQL cnf file:
  read_ini -p mysqlCnf $CNFAUTH

  # Concatenate the parameters for innobackupex:
  USEROPTIONS="--user=$mysqlCnf__client__user --password=$mysqlCnf__client__password"

else

  # Concatenate parameters into innobackupex ones
  USEROPTIONS="--user=$MYUSER"
  if [ ! -z "$MYPASSWD" ]; then USEROPTIONS="$USEROPTIONS --password=$MYPASSWD"; fi

fi

# Connection parameters:
if [ ! -z "$MYHOST" ]; then USEROPTIONS="$USEROPTIONS --host=$MYHOST"; fi
if [ ! -z "$MYPORT" ]; then USEROPTIONS="$USEROPTIONS --port=$MYPORT"; fi
if [ ! -z "$MYSOCKET" ]; then USEROPTIONS="$USEROPTIONS --socket=$MYSOCKET"; fi

# Full and incremental backups directories
FULLBACKUPDIR=$BACKUPDIR/full
INCRBACKUPDIR=$BACKUPDIR/incr

# Check options before proceeding
if [ ! -x $INNOBACKUPEXBINCMD ]; then
  log_msg "$INNOBACKUPEXBINCMD does not exist."
  exit 1
fi

if [ ! -d $BACKUPDIR ]; then
  log_msg "ERROR: Backup destination folder $BACKUPDIR does not exist."
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

# Find latest full backup
LATEST_FULL=`/usr/bin/find $FULLBACKUPDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | /usr/bin/sort -nr | /usr/bin/head -1`

# Get latest backup last modification time
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
    echo "$INNOBACKUPEXBIN failed:"; echo
    echo "---------- ERROR OUTPUT from $INNOBACKUPEXBIN ----------"
    /bin/cat $TMPFILE
    /bin/rm -f $TMPFILE
  else
    log_msg "ERROR: the backup procedure has failed. More details on: $TMPFILE"
  fi
  exit 1
fi

THISBACKUP=`/usr/bin/awk -- "/Backup created in directory/ { split( \\\$0, p, \"'\" ) ; print p[2] }" $TMPFILE`
/bin/rm -f $TMPFILE

log_msg "Databases backed up successfully to: $THISBACKUP"

# Cleanup
log_msg "Cleanup. Keeping only $KEEP full backups and its incrementals."

AGE=$(($FULLBACKUPLIFE * $KEEP / 60))
/usr/bin/find $FULLBACKUPDIR -maxdepth 1 -type d -mmin +$AGE -execdir echo "removing: "$FULLBACKUPDIR/{} \; -execdir rm -rf $FULLBACKUPDIR/{} \; -execdir echo "removing: "$INCRBACKUPDIR/{} \; -execdir rm -rf $INCRBACKUPDIR/{} \;

log_msg "Backup completed."

exit 0
