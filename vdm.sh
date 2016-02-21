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
		localepurge)
			( apt-get install -qy localepurge && configure localepurge ) > /dev/null 2>&1 & showSpinner "> installing localepurge"
			;;
		gcc)
			( apt-get install -qy gcc ) > /dev/null 2>&1 & showSpinner "> installing gcc"
			;;
		build-essential)
			( apt-get install -qy build-essential ) > /dev/null 2>&1 & showSpinner "> installing build-essential"
			;;
		linux-headers-generic)
			( apt-get install -qy linux-headers-generic ) > /dev/null 2>&1 & showSpinner "> installing linux-headers-generic"
			;;
		openssh-server)
			( apt-get install -qy openssh-server ) > /dev/null 2>&1 & showSpinner "> installing openssh-server"
			;;
		deborphan)
			( apt-get install -qy deborphan ) > /dev/null 2>&1 & showSpinner "> installing deborphan"
			;;
		git)
			( apt-get install -qy git && configure git ) > /dev/null 2>&1 & showSpinner "> installing git"
			;;
		virt-what)
			( apt-get install -qy virt-what ) > /dev/null 2>&1 & showSpinner "> installing virt-what"
			;;
		docker)
			configure docker \
			&& update sources

			(
				apt-get remove -qy lxc-docker --purge \
				&& apt-get install -qy linux-image-extra-$(uname -r) docker-engine docker-compose
			) > /dev/null 2>&1 & showSpinner "> installing docker"
			;;
		vmware)
			local target

			getTempDir target "vmware"

        	(
        		rm -rf /tmp/VMWareToolsPatches \
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
		*)
			logError "> Usage: vdm install {localepurge|gcc|build-essential|linux-headers-generic|openssh-server|deborphan|git|virt-what|docker|vmware|virtualbox}"
			exit 1
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

				# @todo check if single interface down & up above work
				# restart interfaces
				# ifdown --exclude=lo -a \
				# && ifup --exclude=lo -a
			) > /dev/null 2>&1 & showSpinner "> configuring interfaces"
			;;
		localepurge)
			(
				if grep -qs NEEDSCONFIGFIRST /etc/locale.nopurge
				then
					local locale=$(locale | grep LANG= | cut -d= -f2)

					echo "${locale}" >> /etc/locale.nopurge
					sed -i -- 's/NEEDSCONFIGFIRST//g' /etc/locale.nopurge
				fi
			) > /dev/null 2>&1 & showSpinner "> configuring localepurge"
			;;
		grub)
			(
				local file="/etc/default/grub"

				grep -q '^GRUB_HIDDEN_TIMEOUT_QUIET=' $file && sed -i 's/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=true/' $file || echo 'GRUB_HIDDEN_TIMEOUT_QUIET=true' >> $file \
				&& grep -q '^GRUB_TIMEOUT=' $file && sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' $file || echo 'GRUB_TIMEOUT=0' >> $file \
				&& grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' $file && sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' $file || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> $file \
				&& grep -q '^GRUB_CMDLINE_LINUX=' $file && sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' $file || echo 'GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"' >> $file \
				&& update-grub
			) > /dev/null 2>&1 & showSpinner "> configuring grub"
			;;
		git)
			(
				if [ ! -f "/etc/gitconfig" ]
				then
					local file="/etc/gitconfig"

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
			) > /dev/null 2>&1 & showSpinner "> configuring git"
			;;
		docker)
			(
				apt-get install -qy apt-transport-https ca-certificates \
				&& apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

				if [ ! -f "/etc/apt/sources.list.d/docker.list" ]
				then
					echo "deb https://apt.dockerproject.org/repo ubuntu-${DISTRO_CODENAME} main" > /etc/apt/sources.list.d/docker.list
				fi
			) > /dev/null 2>&1 & showSpinner "> configuring docker"
			;;
		aliases)
			(
				local file="/etc/profile.d/vdm.sh"

				cat /dev/null > $file
				echo "alias up='docker-compose up -d --timeout 600 && docker-compose logs';" >> $file
				echo "alias down='docker-compose stop --timeout 600';" >> $file
			) > /dev/null 2>&1 & showSpinner "> configuring aliases"
			;;
		runscript)
			(
				local file="/lib/systemd/system/vdm.service"

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

				systemctl enable vdm.service
				systemctl restart vdm.service
			) > /dev/null 2>&1 & showSpinner "> configuring runscript"
			;;
		*)
			logError "> Usage: vdm configure {interfaces|localepurge|grub|git|docker|aliases|runscript}"
			exit 1
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
		vdm)
			exec bash <(curl -s $VDM_URL_UPDATE)
			;;
		*)
			logError "> Usage: vdm update {sources|system|vdm}"
			exit 1
		;;
	esac
}

wipe()
{
	case "$1" in
		kernel)
			( dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | awk 'BEGIN{FS="-"}; {if ($3 ~ /[0-9]+/) print $3"-"$4,$0; else if ($4 ~ /[0-9]+/) print $4"-"$5,$0}' | sort -k1,1 --version-sort -r | sed -e "1,/$(uname -r | cut -f1,2 -d"-")/d" | grep -v -e `uname -r | cut -f1,2 -d"-"` | awk '{print $2}' | xargs apt-get -qy purge ) > /dev/null 2>&1 & showSpinner "> wiping unused kernel"
			;;
		apt)
			( apt-get -qy clean && apt-get -qy autoclean && apt-get -qy autoremove --purge && deborphan | xargs apt-get -qy remove --purge ) > /dev/null 2>&1 & showSpinner "> wiping apt leftovers"
			;;
		temp)
			( rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* ) > /dev/null 2>&1 & showSpinner "> wiping temporary directories"
			;;
		logs)
			(
				find /var/log -type f -regex ".*\.gz$" -exec rm -rf {} \;
				find /var/log -type f -regex ".*\.[0-9]$" -exec rm -rf {} \;
				find /var/log -type f -exec cp /dev/null {} \;

				if [ -d "/var/log/samba" ]
				then
					find /var/log/samba -type f -exec rm -rf {} \;
				fi
			) > /dev/null 2>&1 & showSpinner "> wiping logfiles"
			;;
		container)
			( docker stop -t 600 $(docker ps -a -q -f status=running) ) > /dev/null 2>&1 & showSpinner "> stopping docker container"
			( docker rm $(docker ps -a -q) ) > /dev/null 2>&1 & showSpinner "> wiping docker container"
			;;
		images)
			( docker rmi $(docker images -q) ) > /dev/null 2>&1 & showSpinner "> wiping docker images"
			;;
		mounts)
			(
				rm -rf /vdm

				saveRemove "/mnt/hgfs"
				find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d -exec bash -c 'saveRemove "$@"' bash {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping mount points"
			;;
		vmware)
			(
				if [ -f "/usr/bin/vmware-uninstall-tools.pl" ]
				then
					( /usr/bin/vmware-uninstall-tools.pl ) > /dev/null 2>&1
				fi

				# cleanup
				rm -rf /vmware* \
				&& find /tmp -iname "vmware*" -exec rm -rf {} \; \
				&& find /etc -iname "vmware*" -exec rm -rf {} \; \
				&& find /usr -iname "vmware*" -exec rm -rf {} \; \
				&& find /var -iname "vmware*" -exec rm -rf {} \; \
				&& find /run -iname "vmware*" -exec rm -rf {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping vmware"
			;;
		virtualbox)
			(
				local vbox_version=$(curl -s http://download.virtualbox.org/virtualbox/LATEST.TXT)
				local target_dir
				local target_file

				getTempDir target_dir "virtualbox"
				getTempFile target_file "virtualbox"

				(
					apt-get install -qy dkms build-essential linux-headers-$(uname -r) \
					&& curl -s http://download.virtualbox.org/virtualbox/$vbox_version/VBoxGuestAdditions_$vbox_version.iso > $target_file \
					&& mount -o loop,ro $target_file $target_dir \
					&& $target_dir/VBoxLinuxAdditions.run uninstall --force

					# cleanup
					rm -rf /opt/VBox* \
					&& find /lib -iname "vbox*" -type f -exec rm -rf {} \; \
					&& find /var -iname "vbox*" -type f -exec rm -rf {} \; \
					&& find /run -iname "vbox*" -type f -exec rm -rf {} \;
				) > /dev/null 2>&1 & showSpinner "> wiping virtualbox"
			) > /dev/null 2>&1 & showSpinner "> wiping virtualbox"
			;;
		ssh)
			( rm -rf /etc/ssh/ssh_host_* ) > /dev/null 2>&1 & showSpinner "> wiping ssh keys"
			;;
		data)
			# root user
			(
				history -cw \
				&& cat /dev/null > ~/.bash_history \
				&& find ~/ -name ".ssh" -type d -exec rm -rf {} \; \
				&& find ~/ -name ".docker" -type d -exec rm -rf {} \; \
				&& find ~/ -name ".nano_history" -type f -exec rm -rf {} \;
			) > /dev/null 2>&1 & showSpinner "> wiping private user data (root)"

			# other user
			local userdir

			for userdir in $(find /home -maxdepth 1 -mindepth 1 -type d)
			do
				local username=$(echo "${userdir}" | cut -sd / -f 3-)

				(
					su -l $username -c 'history -cw' \
					&& cat /dev/null > $userdir/.bash_history \
					&& find $userdir -name ".ssh" -type d -exec rm -rf {} \; \
					&& find $userdir -name ".docker" -type d -exec rm -rf {} \; \
					&& find $userdir -name ".nano_history" -type f -exec rm -rf {} \;
				) > /dev/null 2>&1 & showSpinner "> wiping private user data (${username})"
			done

			# locate/mlocate
			( cat /dev/null > /var/lib/mlocate/mlocate.db ) > /dev/null 2>&1 & showSpinner "> wiping mlocate.db"
			;;
		filesystem)
			local target

			getTempFile target "wipe"

			( cat /dev/zero > $target ) > /dev/null 2>&1 & showSpinner "> wiping filesystem"
			;;
		all)
			wipe kernel \
			&& wipe apt \
			&& wipe temp \
			&& wipe logs \
			&& wipe container \
			&& wipe images \
			&& wipe mounts \
			&& wipe vmware \
			&& wipe virtualbox \
			&& wipe ssh \
			&& wipe data \
			&& wipe filesystem
			;;
		*)
			logError "> Usage: vdm wipe {all|kernel|apt|temp|logs|container|images|mounts|vmware|virtualbox|ssh|data|filesystem}"
			exit 1
		;;
	esac
}

case "$1" in
	install)
		case "$2" in
			virtualbox)
				install virtualbox
				;;
			*)
				clear

				logNotice "[VDM] install"

				addgroup vboxsf > /dev/null 2>&1

				for userdir in $(find /home -maxdepth 1 -mindepth 1 -type d)
				do
					username=$(echo "${userdir}" | cut -sd / -f 3-)

					( adduser -q $username vboxsf ) > /dev/null 2>&1
				done

				configure interfaces \
				&& update sources \
				&& install localepurge \
				&& update system \
				&& configure grub \
				&& wipe vmware \
				&& wipe virtualbox \
				&& install git \
				&& install gcc \
				&& install build-essential \
				&& install linux-headers-generic \
				&& install openssh-server \
				&& install deborphan \
				&& install git \
				&& install virt-what \
				&& install docker \
				&& configure aliases \
				&& configure runscript
				;;
		esac
		;;
	update)
		clear

		logNotice "[VDM] update"

		update sources \
		&& update system

		update vdm
		;;
	wipe)
		clear

		logNotice "[VDM] wipe"

		wipe kernel \
		&& wipe apt \
		&& wipe temp \
		&& wipe logs \
		&& wipe container \
		&& wipe images
		;;
	build)
		clear

		logNotice "[VDM] build"

		update sources \
		&& update system \
		&& wipe all

		( sleep 10 && shutdown -h now ) > /dev/null 2>&1 & showSpinner "> shutting down"
		;;
	start)
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

		case $(virt-what | sed -n 1p) in
			vmware)
				if [[ -z $(ps faux | grep -P '(vmware|vmtoolsd)' | grep -v grep | sed -n 1p) ]]
				then
					update sources && install vmware
				fi

				ln -sf /mnt/hgfs /vdm
				;;
			virtualbox)
				symlinkVirtualboxMount()
				{
					target=${1/\/media\/sf_/\/vdm\/}

					ln -sf $1 $target
				}

				export -f symlinkVirtualboxMount

				if [[ -z $(lsmod | grep vboxguest  | sed -n 1p) ]]
				then
					update sources && install virtualbox
				fi

				sleep 5 && find /media -maxdepth 1 -mindepth 1 -name "sf_*" -type d -exec bash -c 'symlinkVirtualboxMount "$@"' bash {} \;
				;;
		esac
		;;
	stop)
		wipe mounts \
		&& wipe container
		;;
	*)
		echo -e "Usage: vdm {install|update|wipe|build}"
		exit 1
		;;
esac

exit 0