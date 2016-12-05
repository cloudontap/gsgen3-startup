#!/bin/bash -x
exec > >(tee /var/log/codeontap/init.log|logger -t codeontap-init -s 2>/dev/console) 2>&1

default_file_system="ext4"                                                    # the default filesystem used if not specified by user
file="/etc/codeontap/facts.sh"                                                # location for facts.sh file.
host_string="cot:name"                                                         # string name to be searched in facts.sh file
host_file="/etc/sysconfig/network"                                            # location to set hostname
instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id`
local_ip=`/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}' |tr "." "-"`
fstab_file="/etc/fstab"

function set_hostname()
{
	grep -q $host_string $file 
	if [[ $? == 0 ]]; then
        host_value=`source $file | grep $host_string | awk -F= '{print $2}'`
        hostname $host_value
        sed -i "s/\(HOSTNAME=\).*/\1$host_value/" $host_file
    else
    	hostname ${instance_id}@${local_ip}
        default_host_value=`echo "$instance_id@$local_ip"`
        sed -i "s/\(HOSTNAME=\).*/\1$default_host_value/" $host_file
    fi
    echo $(hostname)
}

function mountDevice()
{
	device_name=$1
	mount_point=$2
    file_system=$3
    
    if [[ ! -d $mount_point ]]; then
            mkdir $mount_point
    fi

    echo "------${device_name}---$(date)------"
    format_device $device_name $mount_point $file_system
    exit_status=$?
    if [[ "$exit_status" == 1 ]]; then
        return
    fi
    
    mount_device $device_name $mount_point 
    exit_status=$?
    if [[ "$exit_status" == 1 ]]; then
        return
    fi
        
    fstab_mount_entry $device_name $mount_point
    exit_status=$?
    if [[ "$exit_status" == 1 ]]; then
        return
    fi
}

function format_device()
{
    device_name=$1
    mount_point=$2
    file_system=$3
    if [[ ! -b $device_name ]]; then
        echo "device not present"
        return 1
    else
        check_file_system $device_name $mount_point $file_system
    fi
}

function check_file_system()
{
    device_name=$1
    mount_point=$2
    file_system=$3
    if [[ "$file_system" == "" ]]; then
        file  -sL $device_name | grep "ext" > /dev/null
        exit_status=$?
            
        if [[ "$exit_status" == 0 ]]; then
            return 0
        else
            export file_system=$default_file_system                                                                  #assign the default filesystem value if not specified by user while calling the function and device does not have any filesystem.
            echo "formating with $default_file_system filesystem"
        fi

    fi

    local_file_system=`blkid $device_name | grep -oi " type.* " |  awk -F= '{print $2}' | tr -d '"' | tr -d ' '`
    if [[ "$file_system" == "$local_file_system" ]]; then                                                            #compare the filesystem passed by user with the filesystem allocated to the device (if device already has a filesystem). If the values are different then allocate filesystem to device passed by the user. 
        return 0
    else
	if [[ "$file_system" == "$local_file_system" && "$local_file_system" != "" ]]; then
            umount $device_name
	fi
        assign_file_system $device_name $file_system
        exit_status=$?
        if [[ "$exit_status" == 1 ]]; then
            return 1
        fi
        check_file_system $device_name $mount_point $file_system 
    fi
}

function assign_file_system()
{   
    device_name=$1
    file_system=$2
    mkfs.$file_system $device_name
    exit_status=$?
    if [[ "$exit_status" != 0 ]]; then
        echo "file system not applied"
        return 1
    else
        return 0
    fi
}

function mount_device()
{
    device_name=$1
    mount_point=$2
    check_mount_point $device_name $mount_point
    exit_status=$?
    if [[ ! -d $mount_point ]]; then
        mkdir $mount_point
    fi

    if [[ "$exit_status" == 0 ]]; then
    mount $device_name $mount_point 
        if [[ "$?" == 0 ]]; then
            echo "$device_name mounted successfully $mount_point"
        fi
    fi

    exit_status=$?
    if [[ "$exit_status" != 0 ]]; then
        echo "$device_name is not mounted on $mount_point"
        return 1
    else
        return 0
    fi
}

function check_mount_point()
{
    device_name=$1
    mount_point=$2
    mount_status=0
    for local_mount_point in `findmnt -nr -o target -S $device_name`
    do
    if [[ "$local_mount_point" == "$mount_point" ]]; then
        echo "already mounted"
        mount_status=1
        break
    fi
    done
    if [[ "$mount_status" == 1 ]]; then
        return 1
    else
        return 0
    fi
}

function fstab_mount_entry()
{
    device_name=$1
    mount_point=$2
    file_system=$3
    grep  "$device_name" $fstab_file | grep "$mount_point" >  /dev/null
    exit_status=$?
    if [[ "$exit_status" != 0 ]]; then
        file_system=`findmnt -nr -o fstype -S $device_name | head -1`
            
        if [[ $file_system != "" ]]; then
            echo "$device_name $mount_point $file_system defaults 0 0" >> $fstab_file
            echo "now, $device_name is in fstab"
            return 0
        else
            echo "file system is not present"
            return 1
        fi
    else
        echo "$device_name is already exist in fstab"
        return 0
    fi
}

set_hostname
mountDevice /dev/xvdp /codeontap ext4
# For backwards compatability with previous name
ln -s /codeontap /product
mountDevice /dev/xvdc /cache
mountDevice /dev/xvdt /temp




