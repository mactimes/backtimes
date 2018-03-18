#!/usr/bin/env bash

unset PATH


# system commands/utilities paths
DATE=/bin/date
ECHO=/bin/echo
SEQ=/usr/bin/seq
MOUNT=/bin/mount
MKDIR=/bin/mkdir
RM=/bin/rm
FIND=/usr/bin/find
SED=/bin/sed
MV=/bin/mv
CP=/bin/cp
TOUCH=/usr/bin/touch
RSYNC=/usr/bin/rsync


# backup parameters
BACKUP_DEVICE=/dev/sdb1
BACKUP_DIR=/root/backup
SOURCE_DIR=/home
EXCLUDES=/root/excluded
BACKUP_PREFIX='backup'
BACKUP_TIMESTAMP="$($DATE +%Y-%m-%d_%H-%M-%S)"
TOTAL_BACKUPS=3

# script must be run as root/sudo since it is necessary to mount/remount
# partitions and create hard links
if [[ $EUID -ne 0 ]]; then
    $ECHO 'Must be run as root.'
    exit 1
fi

# remount BACKUP_DEVICE read/write at BACKUP_DIR
$MOUNT -o remount,rw $BACKUP_DEVICE $BACKUP_DIR
if (( $? )); then
    $ECHO "backtimes: could not remount $BACKUP_DEVICE read/write at $BACKUP_DIR"
    exit 1
fi


# rotate backups

# create SOURCE_DIR in the BACKUP_DIR if it does not exist yet
if [ ! -d $BACKUP_DIR/$SOURCE_DIR ]; then
    $MKDIR -p $BACKUP_DIR/$SOURCE_DIR
fi

# delete oldest backup if it exists
CURRENT_DIR=$($FIND $BACKUP_DIR$SOURCE_DIR -maxdepth 1 -type d -name $BACKUP_PREFIX-$(( TOTAL_BACKUPS - 1 ))-*)
if [[ -n $CURRENT_DIR ]]; then
    ORIGINAL_TIMESTAMP=${CURRENT_DIR#*$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$(( TOTAL_BACKUPS - 1 ))-}
    if [ -d $BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$(( TOTAL_BACKUPS - 1 ))-$ORIGINAL_TIMESTAMP ]; then
        $RM -rf "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$(( TOTAL_BACKUPS - 1 ))-$ORIGINAL_TIMESTAMP"
    fi
fi

# shift each backup up by one
for BACKUP_INDEX in $($SEQ $(( TOTAL_BACKUPS - 1)) -1 1); do
    CURRENT_DIR=$($FIND $BACKUP_DIR$SOURCE_DIR -maxdepth 1 -type d -name $BACKUP_PREFIX-$BACKUP_INDEX-*)
    if [[ -n $CURRENT_DIR ]]; then
        ORIGINAL_TIMESTAMP=${CURRENT_DIR#*$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$BACKUP_INDEX-}
        $MV "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$BACKUP_INDEX-$ORIGINAL_TIMESTAMP" "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-$(( BACKUP_INDEX + 1 ))-$ORIGINAL_TIMESTAMP"
    fi
done

# create hard link copies of files for the latest backup, if it exists
CURRENT_DIR=$($FIND $BACKUP_DIR$SOURCE_DIR -maxdepth 1 -type d -name $BACKUP_PREFIX-0-*)
if [[ -n $CURRENT_DIR ]]; then
    ORIGINAL_TIMESTAMP=${CURRENT_DIR#*$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-0-}
    $CP -al "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-0-$ORIGINAL_TIMESTAMP" "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-1-$ORIGINAL_TIMESTAMP"
    $MV "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-0-$ORIGINAL_TIMESTAMP" "$BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-0-$BACKUP_TIMESTAMP"
fi


# rsync from SOURCE_DIR to BACKUP_DIR/SOURCE_DIR
$RSYNC -a --delete --delete-excluded --exclude-from="$EXCLUDES" $SOURCE_DIR/ $BACKUP_DIR$SOURCE_DIR/$BACKUP_PREFIX-0-$BACKUP_TIMESTAMP

# update the mtimes of latest backup to reflect the backup time
$TOUCH $BACKUP_DIR/$SOURCE_DIR/$BACKUP_PREFIX-0-$BACKUP_TIMESTAMP

# remount BACKUP_DEVICE as read-only to the BACKUP_DIR
$MOUNT -o remount,ro, $BACKUP_DEVICE $BACKUP_DIR
if (( $? )); then
    $ECHO "backtimes: could not remount $BACKUP_DEVICE as read-only at $BACKUP_DIR"
    exit 1
fi

#EOF
