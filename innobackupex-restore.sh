#!/bin/sh
# 
# Script to prepare and restore full and incremental backups created with innobackupex-runner.
#
# (C)2010 Owen Carter @ Mirabeau BV
# This script is provided as-is; no liability can be accepted for use.
# You are free to modify and reproduce so long as this attribution is preserved.
#
# (C)2013 Benoît LELEVÉ @ Exsellium (www.exsellium.com)
# Adding parameters in order to execute the script in a multiple MySQL instances environment
#

INNOBACKUPEX=innobackupex
INNOBACKUPEXFULL=/usr/bin/$INNOBACKUPEX
TMPFILE="/tmp/innobackupex-restore.$$.tmp"
MEMORY=1024M # Amount of memory to use when preparing the backup
SCRIPTNAME=$(basename "$0")

#############################################################################
# Display usage message and exit
#############################################################################
usage() {
  cat <<EOF
Usage: $SCRIPTNAME [-d backdir] [-f config] [-g group] /absolute/path/to/backup/to/restore
  -d  Directory used to store database backup
  -f  Path to my.cnf database config file
  -g  Group to read from the config file
  -h  Display basic help
EOF
  exit 0
}

# Parse parameters
while getopts ":d:f:g:h" opt; do
  case $opt in
    d )  BACKUPDIR=$OPTARG ;;
    f )  MYCNF=$OPTARG ;;
    g )  MYGROUP=$OPTARG ;;
    h )  usage ;;
    \?)  echo "Invalid option: -$OPTARG"
         echo "For help, type: $SCRIPTNAME -h"
         exit 1 ;;
    : )  echo "Option -$OPTARG requires an argument"
         echo "For help, type: $SCRIPTNAME -h"
         exit 1 ;;
  esac
done

shift $(($OPTIND - 1))

# Check required parameters
if [ -z "$BACKUPDIR" ]; then
  echo "Backup directory is required"
  echo "For help, type: $SCRIPTNAME -h"
  exit 1
fi

if [ -z "$MYCNF" ]; then MYCNF=/etc/mysql/my.cnf; fi
if [ ! -z "$MYGROUP" ]; then DEFGROUP="--defaults-group=$MYGROUP"; fi

# Full and incremental backup directories
FULLBACKUPDIR=$BACKUPDIR/full
INCRBACKUPDIR=$BACKUPDIR/incr

#############################################################################
# Display error message and exit
#############################################################################
error() {
  echo "$1" 1>&2
  exit 1
}

#############################################################################
# Check for errors in innobackupex output
#############################################################################
check_innobackupex_error() {
  if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ]; then
    echo "$INNOBACKUPEX failed:"; echo
    echo "---------- ERROR OUTPUT from $INNOBACKUPEX ----------"
    cat $TMPFILE
    rm -f $TMPFILE
    exit 1
  fi
}

# Check options before proceeding
if [ ! -x $INNOBACKUPEXFULL ]; then
  error "$INNOBACKUPEXFULL does not exist."
fi

if [ ! -d $BACKUPDIR ]; then
  error "Backup destination folder: $BACKUPDIR does not exist."
fi

if [ ! -d $1 ]; then
  error "Backup to restore: $1 does not exist."
fi

# Some info output
echo "----------------------------"
echo
echo "$SCRIPTNAME: MySQL backup script"
echo "started: `date`"
echo

PARENT_DIR=`dirname $1`

if [ $PARENT_DIR = $FULLBACKUPDIR ]; then
  FULLBACKUP=$1
  
  echo "Restore `basename $FULLBACKUP`"
  echo
else
  if [ `dirname $PARENT_DIR` = $INCRBACKUPDIR ]; then
    INCR=`basename $1`
    FULL=`basename $PARENT_DIR`
    FULLBACKUP=$FULLBACKUPDIR/$FULL
    
    if [ ! -d $FULLBACKUP ]; then
      error "Full backup: $FULLBACKUP does not exist."
    fi
    
    echo "Restore $FULL up to incremental $INCR"
    echo
    
    echo "Replay committed transactions on full backup"
    $INNOBACKUPEXFULL --defaults-file=$MYCNF $DEFGROUP --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
    
    # Apply incrementals to base backup
    for i in `find $PARENT_DIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n`; do
      echo "Applying $i to full ..."
      $INNOBACKUPEXFULL --defaults-file=$MYCNF $DEFGROUP --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP --incremental-dir=$PARENT_DIR/$i > $TMPFILE 2>&1
      check_innobackupex_error
      
      if [ $INCR = $i ]; then
        break # break. we are restoring up to this incremental.
      fi
    done
  else
    error "unknown backup type"
  fi
fi

echo "Preparing ..."
$INNOBACKUPEXFULL --defaults-file=$MYCNF $DEFGROUP --apply-log --use-memory=$MEMORY $FULLBACKUP > $TMPFILE 2>&1
check_innobackupex_error

echo
echo "Restoring ..."
$INNOBACKUPEXFULL --defaults-file=$MYCNF $DEFGROUP --copy-back $FULLBACKUP > $TMPFILE 2>&1
check_innobackupex_error

rm -f $TMPFILE
echo "Backup restored successfully. You are able to start mysql now."
echo "Verify files ownership in mysql data dir."
echo "Run 'chown -R mysql:mysql /path/to/data/dir' if necessary."
echo
echo "completed: `date`"
exit 0