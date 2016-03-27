#!/bin/bash -ex
# Assumes EIP allocation id is passed as an environment variable
exec > >(tee /var/log/gosource/eip.log|logger -t gosource-eip -s 2>/dev/console) 2>&1
INSTANCE=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=${REGION::-1}

aws ec2 --region ${REGION} associate-address --instance-id ${INSTANCE} --allocation-id ${EIP_ALLOCID} --allow-reassociation
#


