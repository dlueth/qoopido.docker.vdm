#!/bin/bash

DISTRO_NAME=$(lsb_release -is)
DISTRO_CODENAME=$(lsb_release -cs)
DISTRO_VERSION=$(lsb_release -rs)
COLOR_ERROR='\e[91m'
COLOR_NONE='\e[39m'

error()
{
	echo -e "${COLOR_ERROR}$1${COLOR_NONE}" > /dev/stderr
}

if [ ! $DISTRO_NAME = 'Ubuntu' ] || [ ! $DISTRO_VERSION = '15.10' ];
then
	error "> This script targets Ubuntu 15.10 specifically!"
	exit 1
fi

if [ ! $(whoami) = 'root' ];
then
	error "> This script may only be run as root!"
	exit 1
fi

curl -s https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/vdm.sh > /usr/sbin/vdm \
&& chmod +x /usr/sbin/vdm \
&& /usr/sbin/vdm install