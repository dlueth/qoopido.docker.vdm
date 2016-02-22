#!/bin/bash

# @todo check logging options
# @todo check removal of networks on build and re-apply via service

VDM_URL_UPDATE="https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/update.sh"
# VDM_LOG="/var/log/vdm.log"
# VDM_LOG_ERROR="/var/log/vdm.error.log"
DISTRO_NAME=$(lsb_release -is)
DISTRO_CODENAME=$(lsb_release -cs)
DISTRO_VERSION=$(lsb_release -rs)
COLOR_NOTICE='\e[95m'
COLOR_ERROR='\e[91m'
COLOR_NONE='\e[39m'
TEMP_FILES=( )

logDefault()
{
	echo -e "$1" > /dev/stdout
}

logNotice()
{
	echo -e "${COLOR_NOTICE}$1${COLOR_NONE}" > /dev/stdout
}

logError()
{
	echo -e "${COLOR_ERROR}$1${COLOR_NONE}" > /dev/stderr
}

showSpinner()
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

saveRemove()
{
        if grep -qs $1 /proc/mounts;
        then
                umount -l $1 && rm -rf $1
        else
                rm -rf $1
        fi
}

getTempFile()
{
        local path=$(mktemp -t vdm.$2.XXXXXXXX)

        TEMP_FILES+=($path)

        eval $1=$path
}

getTempDir()
{
        local path=$(mktemp -d -t vdm.$2.XXXXXXXX)

        TEMP_FILES+=($path)

        eval $1=$path
}

wipeTemp() {
        for file in "${TEMP_FILES[@]}"
        do
                saveRemove $file
        done
}

export DEBIAN_FRONTEND=noninteractive
export -f saveRemove

trap wipeTemp INT TERM EXIT

if [ ! $DISTRO_NAME = 'Ubuntu' ] || [ ! $DISTRO_VERSION = '15.10' ];
then
	logError "This script targets Ubuntu 15.10 specifically!"
	exit 1
fi

if [ ! $(whoami) = 'root' ];
then
	logError "This script may only be run as root!"
	exit 1
fi

install()
{
	case "$1" in
		virt-what)
			( apt-get install -qy virt-what ) > /dev/null 2>&1 & showSpinner "> installing virt-what"
			;;
		service)
			(
				local file="/lib/systemd/system/vdm.service"

				cat /dev/null > $file
				echo "[Unit]" >> $file
				echo "Description=Virtual Docker Machine (VDM)" >> $file
				echo "Wants=network-online.target" >> $file
				echo "After=network-online.target" >> $file
				echo "[Service]" >> $file
				echo "Type=oneshot" >> $file
				echo "ExecStart=/usr/sbin/vdm service start" >> $file
				echo "ExecStop=/usr/sbin/vdm service stop" >> $file
				echo "RemainAfterExit=yes" >> $file
				echo "[Install]" >> $file
				echo "WantedBy=multi-user.target" >> $file

				systemctl enable systemd-networkd.service
				systemctl restart systemd-networkd.service
				systemctl enable systemd-networkd-wait-online.service
				systemctl restart systemd-networkd-wait-online.service
				systemctl enable vdm.service
				systemctl restart vdm.service
			) > /dev/null 2>&1 & showSpinner "> installing service"
			;;
		virtualbox)
			local vbox_version=$(curl -s http://download.virtualbox.org/virtualbox/LATEST.TXT)
			local target_dir
			local target_file

			getTempDir target_dir "virtualbox"
			getTempFile target_file "virtualbox"

			(
				apt-get install -qy dkms build-essential linux-headers-$(uname -r) \
				&& curl -s http://download.virtualbox.org/virtualbox/$vbox_version/VBoxGuestAdditions_$vbox_version.iso > $target_file \
				&& mount -o loop,ro $target_file $target_dir \
				&& $target_dir/VBoxLinuxAdditions.run uninstall --force \
				&& rm -rf /opt/VBox* \
				&& ( $target_dir/VBoxLinuxAdditions.run --nox11 || true )
			) > /dev/null 2>&1 & showSpinner "> installing virtualbox"
			;;
	esac
}

configure()
{
	case "$1" in
		interfaces)
			(
				local file="/etc/network/interfaces.d/vdm"
				local interface

				cat /dev/null > $file

				for interface in $(ifconfig -a | sed 's/[ \t].*//;/^\(lo\|docker.*\|\)$/d')
				do
					local state=$(grep $interface /etc/network/interfaces)

					if [[ -z "$state" ]]
					then
						echo "auto ${interface}" >> $file
						echo "iface ${interface} inet dhcp" >> $file
						echo "" >> $file

						ifdown $interface && ifup $interface
					fi
				done
			) > /dev/null 2>&1 & showSpinner "> configuring interfaces"
			;;
	esac
}

update()
{
	case "$1" in
		sources)
			( apt-get update -qy ) > /dev/null 2>&1 & showSpinner "> updating sources"
			;;
		system)
			(
				apt-get -qy upgrade \
				&& apt-get -qy dist-upgrade
			) > /dev/null 2>&1 & showSpinner "> updating system"
			;;
	esac
}

case "$1" in
	install)
		logNotice "[VDM] install localepurge"

		configure interfaces \
		&& update sources \
		&& update system \
		&& install virt-what \
		&& install service
		;;
	service)
		case "$2" in
			start)
				case $(virt-what | sed -n 1p) in
					virtualbox)
						if [[ -z $(lsmod | grep vboxguest  | sed -n 1p) ]]
						then
							update sources && install virtualbox
						fi
					;;
				esac
			;;
			stop)

			;;
		esac
		;;
	*)
		logError "Usage: vdm [install|service]"
		exit 1
		;;
esac

exit 0