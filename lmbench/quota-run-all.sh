#! /bin/bash
name=$1

NUM_PROC=8
NUM_CORES=8
TYPE_EXT4=ext4
MNT_OPT_EXT4="-ogrpquota,usrquota,noload,data=writeback,barrier=0"
TYPE_EXT2=ext2
MNT_OPT_EXT2="-ogrpquota,usrquota"
IMG=/tmp/img
MNT=/tmp/mnt
BIN_PATH="./bin/x86_64-linux-gnu"
TESTS="lat_fs_open_close lat_fs_create_unlink lat_fs_chown lat_fs_write_truncate"
TST_OPTS=" -I -U -L 2 -w -W 3 " 
#OPTS=" -I  -L -w -W 3 " 


function create_one_fs
{
    local sz=$1
    local img_path=$2
    local img=$3
    local type=$4
    local MKFS_OPT=$5

    mkdir $img_path 2> /dev/null 
    mount none $img_path -ttmpfs || exit 1
    dd if=/dev/zero of=$img_path/$img bs=1M seek=$sz count=1 2>/dev/null || exit 1
    mkfs.$type -F $img_path/$img $MKFS_OPT > /dev/null  || exit 1
}

function mount_one_fs
{

    local img=$1
    local mnt_path=$2
    local type=$3
    local opt=$4
    
    mkdir -p $mnt_path
    mount $img $mnt_path -oloop $opt || exit 1
}
function umount_one_fs
{
      umount $1
}

function do_quotacheck
{
    local MNT_BASE=$1
    local SINGLE=$2
    local NUM=$3

    if [ $SINGLE != 'S' ] ;then
	for ((i = 0; i < NUM; i++ ));do
	    quotacheck -cug $MNT_BASE/$i || exit 1
	done
    else 
	quotacheck -cug $MNT_BASE || exit 1
    fi

}
function do_quota_on
{
    local MNT_BASE=$1
    local SINGLE=$2
    local NUM=$3

    if [ $SINGLE != 'S' ] ;then
	for ((i = 0; i < NUM; i++ ));do
	    quotaon $MNT_BASE/$i || exit 1
	done
    else 
	quotaon $MNT_BASE/ || exit 1
    fi
}

function do_quota_off
{
    local MNT_BASE=$1
    local SINGLE=$2
    local NUM=$3
    if [ $SINGLE != "S" ] ;then
	for ((i = 0; i < NUM; i++ ));do
	    quotaoff $MNT_BASE/$i || exit 1
	done
    else 
	quotaoff $MNT_BASE/ || exit 1
    fi
}

function run_tests
{
    local NAME=$1
    local MNT_PATH=$2
    local SINGLE=$3

    local MNT_OPT="-D $MNT_PATH"
    mkdir $NAME || exit 1
    uname -a > $NAME/uname
    echo "single=$SINGLE opts='$MNT_OPT $TST_OPTS'" > $NAME/opts
    if [ $SINGLE == 'S' ]; then
	quotaon -p $MNT_PATH > $NAME/quotastat
    else
	for ((i = 0; i < NUM_PROC; i++ ));do
	    quotaon -p $MNT_PATH/$i >> $NAME/quotastat
	done
    fi
    
    for test in $TESTS ; do

	for ((i = 1; i < NUM_CORES; i*= 2 ));do 
	    $BIN_PATH/$test  $MNT_OPT $TST_OPTS -P$i test 2>> $NAME/$test.log
	done
	for ((i = NUM_CORES; i <= NUM_PROC; i*= 2 ));do 
	    $BIN_PATH/$test $MNT_OPT $TST_OPTS -P$i test 2>> $NAME/$test.log
	done
    done
}

function run_one_fs
{
    local TYPE=$1
    local MNT_OPT=$2
    local IMG_PATH=$3
    local MNT_PATH=$4
    local NAME=$5

#### Test for multiple super_block-s
    SINGLE="M"
    for ((i = 0; i < NUM_PROC; i++)); do
	create_one_fs 1024  $IMG_PATH/$i img $TYPE  
	mount_one_fs $IMG_PATH/$i/img $MNT_PATH/$i $TYPE $MNT_OPT  
	chmod -R 777 $MNT_PATH/$i
    done
    do_quotacheck $MNT_PATH $SINGLE $NUM_PROC
    
    run_tests ${NAME}-${TYPE}-$SINGLE-qoff $MNT_PATH $SINGLE

    do_quota_on $MNT_PATH $SINGLE $NUM_PROC
    run_tests ${NAME}-${TYPE}-$SINGLE-qon  $MNT_PATH $SINGLE
    do_quota_off $MNT_PATH $SINGLE $NUM_PROC

    for ((i = 0; i < NUM_PROC; i++)); do
	    umount $MNT_PATH/$i $IMG_PATH/$i || exit 1
    done

#### Single superblock test
    SINGLE="S"

    create_one_fs 10240  $IMG_PATH img $TYPE $MKFS_OPT  
    mount_one_fs $IMG_PATH/img $MNT_PATH $TYPE $MNT_OPT  
    for ((i = 0; i < NUM_PROC; i++)); do
	mkdir $MNT_PATH/$i
    done
    chmod -R 777 $MNT_PATH

    do_quotacheck $MNT_PATH $SINGLE $NUM_PROC

    run_tests ${NAME}-${TYPE}-$SINGLE-qoff $MNT_PATH $SINGLE

    do_quota_on $MNT_PATH $SINGLE $NUM_PROC
    run_tests ${NAME}-${TYPE}-$SINGLE-qon  $MNT_PATH $SINGLE
    do_quota_off $MNT_PATH $SINGLE $NUM_PROC

    umount $MNT_PATH $IMG_PATH || exit 1
}

run_one_fs ext2 $MNT_OPT_EXT2 $IMG $MNT $name
run_one_fs ext4 $MNT_OPT_EXT4 $IMG $MNT $name


