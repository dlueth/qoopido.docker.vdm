alias up='docker-compose up -d --timeout 600 && docker-compose logs';
alias down='docker-compose stop --timeout 600 && docker rm $(docker ps -a -q)';

case $(virt-what | sed -n 1p) in
	vmware)
		if [ $(systemctl is-active vmware-tools.service) = 'inactive' ];
		then
			/usr/sbin/vdm install vmware
		fi

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