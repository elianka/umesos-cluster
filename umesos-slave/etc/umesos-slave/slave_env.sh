#!/bin/sh
export MESOS_HOSTNAME=%{public_ip}
export MESOS_MASTER=%{zk_url}/mesos
export MESOS_IP=%{private_ip}
export MESOS_LOG_DIR=/var/log/mesos
export MESOS_LOGGING_LEVEL=INFO
export MESOS_PORT=%{slave_port}
export MESOS_ATTRIBUTES="azone:%{azone};owner:%{owner}"
export MESOS_CONTAINERIZERS="docker,mesos"
export MESOS_DOCKER_SOCKET=/var/run/docker.sock
export MESOS_DOCKER_KILL_ORPHANS=true
export MESOS_WORK_DIR=/data/umesos/slave
#export MESOS_HOSTNAME_LOOPUP=false
export MESOS_STRICT=true
export MESOS_resources="ports(*):[20000-32000]"
#for private registry
#export MESOS_DOCKER_CONFIG=file:///root/.docker/config.json
export MESOS_RECOVERY_TIMEOUT=15mins
export MESOS_EXECUTOR_REGISTRATION_TIMEOUT=15mins
