#!/bin/bash

VDM_URL="https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/vdm.sh"
DISTRO_NAME=$(lsb_release -is)
DISTRO_CODENAME=$(lsb_release -cs)
DISTRO_VERSION=$(lsb_release -rs)
COLOR_ERROR='\e[91m'
COLOR_NONE='\e[39m'

error()
{
	echo -e "${COLOR_ERROR}$1${COLOR_NONE}" > /dev/stderr
}

spinner()
{
    local pid=$!
    local delay=0.75
    local spinstr='|/-\'
    local text=$1
    local count=0

    echo -ne "$text "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    echo -ne "\b\b\b\n"
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

(
	curl -s $VDM_URL > /usr/sbin/vdm \
	&& chmod +x /usr/sbin/vdm
)  > /dev/null 2>&1 & spinner "> updating vdm"