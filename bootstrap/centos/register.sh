#!/bin/bash -ex
# Assumes load balancer is passed as an environment variable
exec > >(tee /var/log/codeontap/register.log|logger -t codeontap-register -s 2>/dev/console) 2>&1
INSTANCE=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
aws elb register-instances-with-load-balancer --load-balancer-name $LOAD_BALANCER --instances $INSTANCE
#


