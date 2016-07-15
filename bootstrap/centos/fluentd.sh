#!/bin/bash -ex
exec > >(tee /var/log/gosource/fluentd.log|logger -t gosource-fluentd -s 2>/dev/console) 2>&1

# Increase ulimit as per http://docs.fluentd.org/articles/install-by-rpm 
cp -p /opt/gosource/bootstrap/fluentd/fluentd-limits.conf /etc/security/limits.d/

# Install the Treasure Data repo
rpm --import https://packages.treasuredata.com/GPG-KEY-td-agent
cp -p /opt/gosource/bootstrap/fluentd/treasuredata.repo /etc/yum.repos.d/

# Some key values to add to each log
#	Ideally the project/container/tier/component/subcomponent fields should come
#	from the tag field (via ${tag_parts[n] in the record_transformer filter) but
#	we are waiting for CloudFormation to support for log driver information
#	so for now we will use the facts.sh file
#
HOST=$(hostname | cut -d '@' -f 1)
PROJECT=$(/etc/gosource/facts.sh | grep gs:project= | cut -d '=' -f 2)
SEGMENT=$(/etc/gosource/facts.sh | grep gs:segment= | cut -d '=' -f 2)
TIER=$(/etc/gosource/facts.sh | grep gs:tier= | cut -d '=' -f 2)
COMPONENT=$(/etc/gosource/facts.sh | grep gs:component= | cut -d '=' -f 2)
SUBCOMPONENT=""
LOGS=$(/etc/gosource/facts.sh | grep gs:logs= | cut -d '=' -f 2)
REGION=$(/etc/gosource/facts.sh | grep gs:region= | cut -d '=' -f 2)

# Only install the agent if a logs bucket has been provided
if [[ "${LOGS}" != "" ]]; then
	# Install the agent
	yum install -y td-agent
	
	# Ensure buffer paths exist
	FLUENTD_ROOT=/project/fluentd
	PENDING=${FLUENTD_ROOT}/s3/pending
	ARCHIVE=${FLUENTD_ROOT}/s3/archive
	mkdir -p ${PENDING}
	mkdir -p ${ARCHIVE}
	chown td-agent:td-agent -R ${FLUENTD_ROOT}/*
	chmod -R 755 ${FLUENTD_ROOT}/*
	
	# Make two copies
	#
	# Pending is for further processing (e.g. via logstash to ElasticSearch)
	#	so files in one directory and can be deleted once processed.
	#
	# Archive is structured hierarchically based on date to permit browsing of
	#	raw logs. Ideally the prefix would be formulated using the time field,
	#	but I haven't worked out how to do that yet so for now the time of
	#	writing to S3 (in UTC) is being used
	#
	cat > /etc/td-agent/td-agent.conf << EOF
<source>
	type forward
	port 24224
	bind 127.0.0.1
</source>

<filter *.**>
	type record_transformer
	<record>
	    host ${HOST}
	</record>
</filter>

<filter docker.**>
	type record_transformer
	<record>
	    project ${PROJECT}
	    segment ${SEGMENT}
	    tier ${TIER}
	    component ${COMPONENT}
	    subcomponent ${SUBCOMPONENT}
	</record>
</filter>

<match *.**>
	type copy
	<store>
		type s3
		s3_bucket ${LOGS}
		s3_region ${REGION}
		s3_object_key_format %{path}/%{time_slice}_${HOST}_%{index}.%{file_extension}
		path DOCKERLogs/pending
		buffer_path ${PENDING}/
		
		time_slice_format %Y%m%d_%H%M
		time_slice_wait 5s
		utc
		
		format json
		include_time_key true
		include_tag_key true
	</store>
	<store>
		type s3
		s3_bucket ${LOGS}
		s3_region ${REGION}
		s3_object_key_format %{path}/%{time_slice}/${HOST}_%{uuid_flush}.%{file_extension}
		path DOCKERLogs/archive
		buffer_path ${ARCHIVE}/
		
		time_slice_format %Y%m/%d/%H
		time_slice_wait 5m
		utc
		
		format json
		include_time_key true
		include_tag_key true
	</store>
</match>
EOF

	# Start the agent - install makes sure it runs on reboot
	service td-agent start
	
	# Wait a bit to let the daemon get started so it is there when docker/ECS checks
	sleep 5s
fi

