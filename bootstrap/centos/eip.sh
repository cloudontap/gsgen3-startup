#!/bin/bash -x
# Assumes one or more EIP allocation ids are passed as an environment variable
exec > >(tee /var/log/codeontap/eip.log|logger -t codeontap-eip -s 2>/dev/console) 2>&1
INSTANCE=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=${REGION::-1}

# Loop through the provided ids looking to a free one
UNALLOCATED=1
for ID in ${EIP_ALLOCID}; do
	aws ec2 --region ${REGION} describe-addresses --allocation-id ${ID} | grep "AssociationId"
	RESULT=$?
	if [[ ${RESULT} -ne 0 ]]; then
		# Address is free - grab it
		aws ec2 --region ${REGION} associate-address --instance-id ${INSTANCE} --allocation-id ${ID} --no-allow-reassociation
		RESULT=$?
		if [[ ${RESULT} -eq 0 ]]; then
			UNALLOCATED=0
			break
		fi
	fi
done

exit ${UNALLOCATED}

