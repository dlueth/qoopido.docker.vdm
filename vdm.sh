#!/bin/bash

DISTRO_NAME=$(lsb_release -is)
DISTRO_CODENAME=$(lsb_release -cs)
DISTRO_VERSION=$(lsb_release -rs)
#COLOR_LOG='\e[95m'
COLOR_ERROR='\e[91m'
COLOR_NONE='\e[39m'

export DEBIAN_FRONTEND=noninteractive

log()
{
	echo -e "$1" > /dev/stdout
}

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

install()
{
	case "$1" in
		localepurge)
			( apt-get install -qy localepurge && configure localepurge ) > /dev/null 2>&1 & spinner "> installing localepurge"
			;;
		gcc)
			( apt-get install -qy gcc ) > /dev/null 2>&1 & spinner "> installing gcc"
			;;
		build-essential)
			log "> installing build-essential"

			( apt-get install -qy build-essential ) > /dev/null 2>&1 & spinner "> installing build-essential"
			;;
		linux-headers-generic)
			( apt-get install -qy linux-headers-generic ) > /dev/null 2>&1 & spinner "> installing linux-headers-generic"
			;;
		openssh-server)
			log "> installing openssh-server"

			( apt-get install -qy openssh-server ) > /dev/null 2>&1 & spinner "> installing openssh-server"
			;;
		deborphan)
			( apt-get install -qy deborphan ) > /dev/null 2>&1 & spinner "> installing deborphan"
			;;
		git)
			( apt-get install -qy git && configure git ) > /dev/null 2>&1 & spinner "> installing git"
			;;
		virt-what)
			( apt-get install -qy virt-what ) > /dev/null 2>&1 & spinner "> installing virt-what"
			;;
		docker)
			configure docker

			(
				apt-get remove lxc-docker --purge \
				&& apt-get install linux-image-extra-$(uname -r) \
				&& apt-get install docker-engine \
				&& apt-get install docker-compose
			) > /dev/null 2>&1 & spinner "> installing docker"
			;;
		*)
			error "> Usage: vdm install {localepurge|gcc|build-essential|linux-headers-generic|openssh-server|deborphan|git|virt-what|docker}"
			exit 1
		;;
	esac
}

configure()
{
	case "$1" in
		interfaces)
			log "> configuring interfaces"

			# interfaces=($(ifconfig -a | sed 's/[ \t].*//;/^\(lo\|docker.*\|\)$/d'))

			# for interface in "${interfaces[@]}"
			for interface in $(ifconfig -a | sed 's/[ \t].*//;/^\(lo\|docker.*\|\)$/d')
			do
				state=$(grep $interface /etc/network/interfaces)

				if [[ -z "$state" ]]
				then
					echo "" >> /etc/network/interfaces
					echo "auto ${interface}" >> /etc/network/interfaces
					echo "iface ${interface} inet dhcp" >> /etc/network/interfaces
				fi
			done
			;;
		localepurge)
			log "> configuring localepurge"

			if grep -qs NEEDSCONFIGFIRST /etc/locale.nopurge
			then
				locale=$(locale | grep LANG= | cut -d= -f2)

				echo "${locale}" >> /etc/locale.nopurge
				sed -i -- 's/NEEDSCONFIGFIRST//g' /etc/locale.nopurge
			fi
			;;
		grub)
			log "> configuring grub"
			file="/etc/default/grub"

			(
				grep -q '^GRUB_HIDDEN_TIMEOUT_QUIET=' $file && sed -i 's/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=true/' $file || echo 'GRUB_HIDDEN_TIMEOUT_QUIET=true' >> $file \
				&& grep -q '^GRUB_TIMEOUT=' $file && sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' $file || echo 'GRUB_TIMEOUT=0' >> $file \
				&& grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' $file && sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' $file || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> $file \
				&& grep -q '^GRUB_CMDLINE_LINUX=' $file && sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' $file || echo 'GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"' >> $file \
				&& update-grub
			) > /dev/null 2>&1
			;;
		git)
			log "> configuring git"

			if [ ! -f "/etc/gitconfig" ]
			then
				file="/etc/gitconfig"

				cat /dev/null > $file
				echo "[pack]" >> $file
				echo "threads = 1" >> $file
				echo "deltaCacheSize = 128m" >> $file
				echo "packSizeLimit = 128m" >> $file
				echo "windowMemory = 128m" >> $file
				echo "[core]" >> $file
				echo "packedGitLimit = 128m" >> $file
				echo "packedGitWindowSize = 128m" >> $file
			fi
			;;
		docker)
			log "> configuring docker"

			(
				apt-get install -qy apt-transport-https ca-certificates \
				&& apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
			) > /dev/null 2>&1

			if [ ! -f "/etc/apt/sources.list.d/docker.list" ]
			then
				echo "deb https://apt.dockerproject.org/repo ubuntu-${DISTRO_CODENAME} main" > /etc/apt/sources.list.d/docker.list
			fi
			;;
		runscript)
			log "> configuring runscript"

			file="/lib/systemd/system/vdm.service"

			cat /dev/null > $file
			echo "[Unit]" >> $file
			echo "Description=Virtual Docker Machine (VDM)" >> $file
			echo "[Service]" >> $file
			echo "Type=oneshot" >> $file
			echo "ExecStart=/usr/sbin/vdm start" >> $file
			echo "ExecStop=/usr/sbin/vdm stop" >> $file
			echo "RemainAfterExit=yes" >> $file
			echo "[Install]" >> $file
			echo "WantedBy=multi-user.target" >> $file

			( systemctl enable vdm.service ) > /dev/null 2>&1
			;;
		*)
			error "> Usage: vdm configure {interfaces|localepurge|grub|git|docker}"
			exit 1
			;;
	esac
}

update()
{
	case "$1" in
		vdm)
			( curl -s https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/development/vdm.sh > /usr/sbin/vdm && chmod +x /usr/sbin/vdm ) > /dev/null 2>&1 & spinner "> updating vdm"
			;;
		sources)
			( apt-get update -qy ) > /dev/null 2>&1 & spinner "> updating sources"
			;;
		system)
			( apt-get -qy upgrade && apt-get -qy dist-upgrade ) > /dev/null 2>&1 & spinner "> updating system"
			;;
		*)
			error "> Usage: vdm update {sources|system}"
			exit 1
		;;
	esac
}

clear()
{
	case "$1" in
		kernel)
			( dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | awk 'BEGIN{FS="-"}; {if ($3 ~ /[0-9]+/) print $3"-"$4,$0; else if ($4 ~ /[0-9]+/) print $4"-"$5,$0}' | sort -k1,1 --version-sort -r | sed -e "1,/$(uname -r | cut -f1,2 -d"-")/d" | grep -v -e `uname -r | cut -f1,2 -d"-"` | awk '{print $2}' | xargs apt-get -qy purge ) > /dev/null 2>&1 & spinner "> clearing unused kernel"
			;;
		apt)
			( apt-get -qy clean && apt-get -qy autoclean && apt-get -qy autoremove --purge && deborphan | xargs apt-get -qy remove --purge ) > /dev/null 2>&1 & spinner "> clearing apt leftovers"
			;;
		temp)
			( rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* ) > /dev/null 2>&1 & spinner "> clearing temporary directories"
			;;
		logs)
			log "> clearing logfiles"

			# remove .gz files
			for file in $(find /var/log -type f -regex ".*\.gz$")
			do
				rm -rf $file
			done

			# remove rotated logfiles
			for file in $(find /var/log -type f -regex ".*\.[0-9]$")
			do
				rm -rf $file
			done

			# remove samba logs (might leak ip-adresses)
			if [ -d "/var/log/samba" ]
			then
				for file in $(find /var/log/samba -type f)
				do
					rm -rf $file
				done
			fi

			# empty remaining
			for file in $(find /var/log/ -type f)
			do
				cp /dev/null $file
			done
			;;
		container)
			( docker rm $(docker ps -a -q) ) > /dev/null 2>&1 & spinner "> clearing docker container"
			;;
		images)
			( docker rmi $(docker images -q) ) > /dev/null 2>&1 & spinner "> clearing docker images"
			;;
		mounts)
			log "> clearing mount points"

			rm -rf /vdm

			# VMWare
			if [ -d "/mnt/hgfs" ]
			then
				if grep -qs '/mnt/hgfs' /proc/mounts;
				then
					( umount -l /mnt/hgfs && rm -rf /mnt/hgfs ) > /dev/null 2>&1
				else
					rm -rf /mnt/hgfs
				fi
			fi

			# VirtualBox
			for source in $(find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d)
			do
				if grep -qs $source /proc/mounts;
				then
					( umount -l $source && rm -rf $source ) > /dev/null 2>&1
				else
					rm -rf $source
				fi
			done
			;;
		ssh)
			( rm -rf /etc/ssh/ssh_host_* ) > /dev/null 2>&1 & spinner "> clearing ssh keys"
			;;
		data)
			# root user
			(
				history -cw \
				&& cat /dev/null > ~/.bash_history \
				&& find ~/ -name ".ssh" -type d -exec rm -rf {} \; \
				&& find ~/ -name ".docker" -type d -exec rm -rf {} \; \
				&& find ~/ -name ".nano_history" -type f -exec rm -rf {} \;
			) > /dev/null 2>&1 & spinner "> clearing private user data (root)"

			# other user
			for userdir in $(find /home -maxdepth 1 -mindepth 1 -type d)
			do
				username=$(echo "${userdir}" | cut -sd / -f 3-)

				(
					su -l $username -c 'history -cw' \
					&& cat /dev/null > $userdir/.bash_history \
					&& find $userdir -name ".ssh" -type d -exec rm -rf {} \; \
					&& find $userdir -name ".docker" -type d -exec rm -rf {} \; \
					&& find $userdir -name ".nano_history" -type f -exec rm -rf {} \;
				) > /dev/null 2>&1 & spinner "> clearing private user data (${username})"
			done

			# locate/mlocate
			( cat /dev/null > /var/lib/mlocate/mlocate.db ) > /dev/null 2>&1 & spinner "> clearing mlocate.db"
			;;
		filesystem)
			( cat /dev/zero > /tmp/zero.file ) > /dev/null 2>&1 & spinner "> clearing filesystem"

			rm -rf /tmp/zero.file
			;;
		all)
			clear kernel \
			&& clear apt \
			&& clear temp \
			&& clear logs \
			&& clear container \
			&& clear images \
			&& clear mounts \
			&& clear ssh \
			&& clear data \
			&& clear filesystem
			;;
		*)
			error "> Usage: vdm clear {all|kernel|apt|temp|logs|container|images|mounts|ssh|data|filesystem}"
			exit 1
		;;
	esac
}

case "$1" in
	install)
		configure interfaces \
		&& update vdm \
		&& update sources \
		&& install localepurge \
		&& update system \
		&& configure grub \
		&& install git \
		&& install gcc \
		&& install build-essential \
		&& install linux-headers-generic \
		&& install openssh-server \
		&& install deborphan \
		&& install git \
		&& install virt-what \
		&& install docker \
		&& configure runscript
		;;
	update)
		update vdm \
		&& update sources \
		&& update system
		;;
	clear)
		clear kernel \
		&& clear apt \
		&& clear temp \
		&& clear logs \
		&& clear container \
		&& clear images
		;;
	build)
		update sources \
		&& update system \
		&& clear all

		( sleep 10 && shutdown -h now ) > /dev/null 2>&1 & spinner "> shutting down for export"
		;;
	start)
		vm=$(virt-what | sed -n 1p)

		# Generate SSH keys
		if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]
		then
			rm -rf /etc/ssh/ssh_host_rsa_key*
			ssh-keygen -q -h -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
		fi

		if [ ! -f "/etc/ssh/ssh_host_dsa_key" ]
		then
			rm -rf /etc/ssh/ssh_host_dsa_key*
			ssh-keygen -q -h -f /etc/ssh/ssh_host_dsa_key -N '' -t dsa
		fi

		if [ ! -f "/etc/ssh/ssh_host_ecdsa_key" ]
		then
			rm -rf /etc/ssh/ssh_host_ecdsa_key*
			ssh-keygen -q -h -f /etc/ssh/ssh_host_ecdsa_key -N '' -t ecdsa
		fi

		if [ ! -f "/etc/ssh/ssh_host_ed25519_key" ]
		then
			rm -rf /etc/ssh/ssh_host_ed25519_key*
			ssh-keygen -q -h -f /etc/ssh/ssh_host_ed25519_key -N '' -t ed25519
		fi

		# Initialize mounts
		mkdir -p /vdm

		case $vm in
			vmware)
				ln -sf /mnt/hgfs /shared
				;;
			virtualbox)
				state=$(lsmod | grep vboxguest | sed -n 1p)

				if [[ -z "$state" ]]
				then
					vbox_version=$(curl -s http://download.virtualbox.org/virtualbox/LATEST.TXT)
					vbox_name="VBoxGuestAdditions_${vbox_version}"

					(
						( curl -s http://download.virtualbox.org/virtualbox/$vbox_version/$vbox_name.iso > /tmp/$vbox_name.iso ) \
						&& ( mkdir -p /tmp/$vbox_name && mount -o loop,ro /tmp/$vbox_name.iso /tmp/$vbox_name && /tmp/$vbox_name/VBoxLinuxAdditions.run uninstall --force && rm -rf /opt/VBox* ) \
						&& ( /tmp/$vbox_name/VBoxLinuxAdditions.run --nox11 || true ) \
						&& ( umount -l /tmp/$vbox_name && rm -rf /tmp/* )
					) > /dev/null 2>&1 & spinner "> installing VirtualBox Guest Additions"
				fi

				#mounts=($(find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d))

				#for source in "${mounts[@]}"
				for source in $(find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d)
				do
					target=${source/\/media\/sf_/\/shared\/}

					ln -sf $source $target
				done
				;;
		esac
		;;
	stop)
		clear mounts \
		&& clear container
		;;
	*)
		echo -e "Usage: vdm {install|update|clear|build}"
		exit 1
		;;
esac

exit 0