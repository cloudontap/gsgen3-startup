#!/bin/bash -ex
# Configure puppet 
# First 
# Bacially all we do is the initial puppet apply, and then puppet should look 
# after itself, including installing cron jobs to run it regularly
exec > >(tee /var/log/codeontap/puppet.log|logger -t codeontap-puppet -s 2>/dev/console) 2>&1
echo Running $0
#

