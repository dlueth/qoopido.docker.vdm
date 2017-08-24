#!/bin/bash
set -e

UUID=$(cat /proc/sys/kernel/random/uuid)
VDM_URL="https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/update.sh?uuid=${UUID}"
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
		deborphan)
			(
				apt-get install -qy deborphan
			) > /dev/null 2>&1 & showSpinner "> installing deborphan"
		;;
		openssh-server)
			(
				apt-get install -qy openssh-server
			) > /dev/null 2>&1 & showSpinner "> installing openssh-server"
		;;
		nfs-common)
			(
				apt-get install -qy nfs-common
			) > /dev/null 2>&1 & showSpinner "> installing nfs-common"
		;;
		virt-what)
			(
				apt-get install -qy virt-what
			) > /dev/null 2>&1 & showSpinner "> installing virt-what"
		;;
		docker)
			(
				local file="/etc/apt/sources.list.d/vdm.list"
				local url=$(curl -s https://api.github.com/repos/docker/compose/releases | grep browser_download_url | grep 'Linux-x86_64' | head -n 1 | cut -d '"' -f 4)

				if [ ! -f $file ]
				then
					echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${DISTRO_CODENAME} stable" > $file
				fi

				apt-get install -qy apt-transport-https ca-certificates software-properties-common \
				&& curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
				&& update sources \
				&& apt-get remove -qy lxc-docker --purge \
				&& apt-get install -qy docker-ce \
				&& curl -fsSL -o /usr/local/bin/docker-compose ${url} \
				&& chmod +x /usr/local/bin/docker-compose

				groupadd docker > /dev/null 2>&1

				for user in $(cut -d: -f1 /etc/passwd)
				do
				    usermod -a -G docker $user
				done

				service docker restart
				newgrp docker
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

				groupadd vboxsf > /dev/null 2>&1

				for user in $(cut -d: -f1 /etc/passwd)
				do
				    usermod -a -G vboxsf $user
				done

				newgrp vboxsf
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
				systemctl restart vdm.service &
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
				echo "alias down='docker-compose stop --timeout 600 && (docker-compose rm -f) > /dev/null 2>&1';" >> $file

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
				exec bash <(curl -s $VDM_URL) \
				&& configure vdm
			) > /dev/null 2>&1 & showSpinner "> updating vdm"
		;;
	esac
}

wipe()
{
	case "$1" in
		docker)
			(
				docker stop -t 600 $(docker ps -a -q -f status=running)
			) > /dev/null 2>&1 & showSpinner "> stopping docker container"

			(
				docker ps -a -q | xargs -r docker rm \
				&& docker images -q | xargs -r docker rmi \
				&& docker volume ls -qf dangling=true | xargs -r docker volume rm \
				&& docker system prune --force \
				&& systemctl stop docker \
				&& rm -rf /var/lib/docker/aufs \
				&& systemctl start docker
			) > /dev/null 2>&1 & showSpinner "> wiping docker container & images"
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
				&& find /etc ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /sbin ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /usr ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /lib ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /var ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /run ! -readable -prune -iname "*vbox*" -type d -exec rm -rf {} \; \
				&& find /etc ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \; \
				&& find /sbin ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \; \
				&& find /usr ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \; \
				&& find /lib ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \; \
				&& find /var ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \; \
				&& find /run ! -readable -prune -iname "*vbox*" -type f -exec rm -rf {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping virtualbox"
		;;
	esac
}

clean()
{
		wipe docker

        (
        	rm -rf /tmp/* /var/tmp/* \
        	&& dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | awk 'BEGIN{FS="-"}; {if ($3 ~ /[0-9]+/) print $3"-"$4,$0; else if ($4 ~ /[0-9]+/) print $4"-"$5,$0}' | sort -k1,1 --version-sort -r | sed -e "1,/$(uname -r | cut -f1,2 -d"-")/d" | grep -v -e `uname -r | cut -f1,2 -d"-"` | awk '{print $2}' | xargs apt-get -qy purge \
        	&& apt-get -qy clean \
        	&& apt-get -qy autoclean \
        	&& apt-get -qy autoremove \
        	&& deborphan | xargs apt-get -qy remove --purge
        ) > /dev/null 2>&1 & showSpinner "> cleaning up"
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

				configure interfaces \
				&& update sources \
				&& update system \
				&& wipe vmware \
				&& wipe virtualbox \
				&& install openssh-server \
				&& install nfs-common \
				&& install virt-what \
				&& install docker \
				&& install deborphan \
				&& install service \
				&& {
					case $(virt-what | sed -n 1p) in
						vmware)
							install vmware
						;;
						virtualbox)
							install virtualbox
						;;
					esac
				} \
				&& configure vdm \
				&& clean

				logNotice "> please reboot"
			;;
		esac
	;;
	cleanup)
		logNotice "[VDM] clean"

		clean
	;;
	update)
		logNotice "[VDM] update"

		update sources \
		&& update system \
		&& update vdm \
		&& clean

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
						symlinkVirtualboxMount()
						{
							target=${1/\/media\/sf_/\/vdm\/}

							ln -sf $1 $target
						}

						export -f symlinkVirtualboxMount

						find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d -exec bash -c 'symlinkVirtualboxMount "$@"' bash {} \;
					;;
				esac
			;;
			stop)
				wipe docker \
				&& find /vdm -maxdepth 1 -mindepth 1 -type d -exec bash -c 'saveRemove "$@"' bash {} \;
			;;
			*)
				logError "Usage: vdm service [start|stop]"
				exit 1
				;;
		esac
		;;
	*)
		logError "Usage: vdm [install|update|cleanup|service]"
		exit 1
	;;
esac

exit 0
