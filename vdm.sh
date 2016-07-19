#!/bin/bash

# @todo check logging options
# @todo check removal of networks on build and re-apply via service

# http://linuxcommand.org/wss0150.php
# http://askubuntu.com/questions/323566/separate-etc-network-interfaces-file
# http://tldp.org/HOWTO/Bash-Prog-Intro-HOWTO-3.html#ss3.3


VDM_URL="https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/update.sh"
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

if [ ! $DISTRO_NAME = 'Ubuntu' ] || [ ! $DISTRO_VERSION = '16.04' ];
then
	logError "This script targets Ubuntu 16.04 specifically!"
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
		openssh-server)
			(
				apt-get install -qy openssh-server
			) > /dev/null 2>&1 & showSpinner "> installing openssh-server"
		;;
		virt-what)
			(
				apt-get install -qy virt-what
			) > /dev/null 2>&1 & showSpinner "> installing virt-what"
		;;
		docker)
			(
				local file="/etc/apt/sources.list.d/vdm.list"

				if [ ! -f $file ]
				then
					echo "deb https://apt.dockerproject.org/repo ubuntu-${DISTRO_CODENAME} main" > $file
				fi

				apt-get install -qy apt-transport-https ca-certificates \
				&& apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D \
				&& update sources \
				&& apt-get remove -qy lxc-docker --purge \
				&& apt-get install -qy linux-image-extra-$(uname -r) docker-engine docker-compose
			) > /dev/null 2>&1 & showSpinner "> installing docker"
		;;
		git)
			(
				apt-get install -qy git \
				&& configure git
			) > /dev/null 2>&1 & showSpinner "> configuring git"
		;;
		vmware)
        	(
        		local target

				getTempDir target "vmware"

        		install git \
        		&& apt-get install -qy zip \
        		&& git clone https://github.com/rasa/vmware-tools-patches.git $target \
        		&& cd $target \
        		&& . ./setup.sh \
        		&& ./download-tools.sh latest \
        		&& ./untar-and-patch.sh \
        		&& ./compile.sh
        	) > /dev/null 2>&1 & showSpinner "> installing vmware"
		;;
		virtualbox)
			(
				local vbox_version=$(curl -s http://download.virtualbox.org/virtualbox/LATEST.TXT)
				local target_dir
				local target_file

				getTempDir target_dir "virtualbox"
				getTempFile target_file "virtualbox"

				apt-get install -qy dkms build-essential linux-headers-$(uname -r) \
				&& curl -s http://download.virtualbox.org/virtualbox/$vbox_version/VBoxGuestAdditions_$vbox_version.iso > $target_file \
				&& mount -o loop,ro $target_file $target_dir \
				&& ( $target_dir/VBoxLinuxAdditions.run --nox11 || true )
			) > /dev/null 2>&1 & showSpinner "> installing virtualbox"
		;;
		service)
			(
				local file="/lib/systemd/system/vdm.service"

				cat /dev/null > $file
				echo "[Unit]" >> $file
				echo "Description=Virtual Docker Machine (VDM)" >> $file
				echo "[Service]" >> $file
				echo "Type=oneshot" >> $file
				echo "ExecStart=/usr/sbin/vdm service start" >> $file
				echo "ExecStop=/usr/sbin/vdm service stop" >> $file
				echo "RemainAfterExit=yes" >> $file
				echo "[Install]" >> $file
				echo "WantedBy=multi-user.target" >> $file

				systemctl enable vdm.service
			) > /dev/null 2>&1 & showSpinner "> installing service"
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

				systemctl restart systemd-networkd.service

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

				systemctl restart systemd-networkd.service
			) > /dev/null 2>&1 & showSpinner "> configuring interfaces"
		;;
		vdm)
			(
				local file="/etc/profile.d/vdm.sh"

				cat /dev/null > $file
				echo "alias up='docker-compose up -d --timeout 600 && docker-compose logs';" >> $file
				echo "alias down='docker-compose stop --timeout 600 && (docker rm $(docker ps -a -q)) > /dev/null 2>&1';" >> $file

				chmod +x $file
			) > /dev/null 2>&1 & showSpinner "> configuring vdm"
		;;
		git)
			(
				local file="/etc/gitconfig"

				if [ ! -f $file ]
				then
					cat /dev/null > $file
					echo "[pack]" >> $file
					echo "threads = 1" >> $file
					echo "deltaCacheSize = 1024m" >> $file
					echo "packSizeLimit = 1024m" >> $file
					echo "windowMemory = 1024m" >> $file
					echo "[core]" >> $file
					echo "packedGitLimit = 1024m" >> $file
					echo "packedGitWindowSize = 1024m" >> $file
				fi
			) > /dev/null 2>&1 & showSpinner "> configuring git"
		;;
	esac
}

update()
{
	case "$1" in
		sources)
			(
				apt-get -qy update
			) > /dev/null 2>&1 & showSpinner "> updating sources"
		;;
		system)
			(
				apt-get -qy upgrade \
				&& apt-get -qy dist-upgrade \
				&& service lxd restart
			) > /dev/null 2>&1 & showSpinner "> updating system"
		;;
		vdm)
			(
				exec bash <(curl -s $VDM_URL_UPDATE) \
				&& configure vdm
			) > /dev/null 2>&1 & showSpinner "> updating vdm"
		;;
	esac
}

wipe()
{
	case "$1" in
		container)
			(
				docker stop -t 600 $(docker ps -a -q -f status=running)
			) > /dev/null 2>&1 & showSpinner "> stopping docker container"

			(
				docker rm $(docker ps -a -q)
			) > /dev/null 2>&1 & showSpinner "> wiping docker container"
		;;
		images)
			(
				docker rmi $(docker images -q)
			) > /dev/null 2>&1 & showSpinner "> wiping docker images"
		;;
		vmware)
			(
				if [ -f "/usr/bin/vmware-uninstall-tools.pl" ]
				then
					(
						/usr/bin/vmware-uninstall-tools.pl
					) > /dev/null 2>&1
				fi

				# cleanup
				rm -rf /vmware* \
				&& find /lib ! -readable -prune -iname "vmware*" -exec rm -rf {} \; \
				&& find /var ! -readable -prune -iname "vmware*" -exec rm -rf {} \; \
				&& find /run ! -readable -prune -iname "vmware*" -exec rm -rf {} \; \
				&& find /usr ! -readable -prune -iname "vmware*" -exec rm -rf {} \; \
				&& find /etc ! -readable -prune -iname "vmware*" -exec rm -rf {} \; \
				&& find /tmp ! -readable -prune -iname "vmware*" -exec rm -rf {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping vmware"
		;;
		virtualbox)
			(
				local service
				local module

				# stop & disable related services
				for service in $(systemctl | egrep -io '^vbox[a-z0-9-]+\.service')
				do
					systemctl stop $service
					systemctl disable $service
				done

				# remove modules having dependencies
				for module in $(lsmod | egrep -io vbox[a-z0-9-]+$)
				do
					modprobe -r $module
				done

				# remove modules without dependencies
				for module in $(lsmod | egrep -io ^vbox[a-z0-9-]+)
				do
					modprobe -r $module
				done

				# remove filesystem remains
				rm -rf /opt/VBox* \
				&& find /lib ! -readable -prune -iname "vbox*" -type f -exec rm -rf {} \; \
				&& find /var ! -readable -prune -iname "vbox*" -type f -exec rm -rf {} \; \
				&& find /run ! -readable -prune -iname "vbox*" -type f -exec rm -rf {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping virtualbox"
		;;
	esac
}

case "$1" in
	install)
		case "$2" in
			vmware)
				wipe vmware
				install vmware
			;;
			virtualbox)
				wipe virtualbox
				install virtualbox
			;;
			*)
				logNotice "[VDM] install"

				configure interfaces
				update sources
				update system
				install openssh-server
				install virt-what
				install docker
				install service

				case $(virt-what | sed -n 1p) in
					vmware)
						wipe vmware
						install vmware
					;;
					virtualbox)
						wipe virtualbox
						install virtualbox
					;;
				esac

				configure vdm

				logNotice "> please reboot"
			;;
		esac
	;;
	update)
		logNotice "[VDM] update"

		update sources \
		&& update system \
		&& update vdm

		logNotice "> please reboot"
	;;
	service)
		case "$2" in
			start)
				mkdir -p /vdm

				case $(virt-what | sed -n 1p) in
					vmware)
						while [ ! -d /mnt/hgfs ]
						do
							sleep 1
						done

						symlinkVmwareMount()
						{
							target=${1/\/mnt\/hgfs\//\/vdm\/}

							ln -sf $1 $target
						}

						export -f symlinkVmwareMount

						find /mnt/hgfs -maxdepth 1 -mindepth 1 -type d -exec bash -c 'symlinkVmwareMount "$@"' bash {} \;
					;;
					virtualbox)
				#		if [[ -z $(lsmod | grep vboxguest | sed -n 1p) ]]
				#		then
				#			update sources \
				#			&& install virtualbox
				#		fi

				#		symlinkVirtualboxMount()
				#		{
				#			target=${1/\/media\/sf_/\/vdm\/}

				#			ln -sf $1 $target
				#		}

				#		export -f symlinkVirtualboxMount

				#		find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d -exec bash -c 'symlinkVirtualboxMount "$@"' bash {} \;
					;;
				esac
			;;
			stop)
				wipe container \
				&& find /vdm -maxdepth 1 -mindepth 1 -type d -exec bash -c 'saveRemove "$@"' bash {} \;
			;;
			*)
				logError "Usage: vdm service [start|stop]"
				exit 1
				;;
		esac
		;;
	*)
		logError "Usage: vdm [install|update]"
		exit 1
	;;
esac

exit 0
