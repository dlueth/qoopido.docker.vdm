1. Install VMWare or VirtualBox
2. Download ```https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/master/vdm.ova```...
3. ... and import it <sup id="a1">[1](#f1)</sup> <sup id="a2">[2](#f2)</sup>
4. Download Ubuntu Server 16.04...
5. .. and install it
6. Run ```bash <(curl -s https://raw.githubusercontent.com/dlueth/qoopido.docker.vdm/master/install.sh)``` as ```root``` in your VM
7. Add the shared folders you would like to use in your VM <sup id="a3">[3](#f3)</sup>
8. Reboot your VM

<b id="f1">1)</b>The OVA is generated via VirtualBox so you might get an error importing it into VMWare - simply agree to fix it in VMWare to resolve this issue[↩](#a1)

<b id="f2">2)</b>Make sure your VMs settings for host-only networking adapters are correct [↩](#a2)

<b id="f3">3)</b>Only works flawlessly with VMWare, using NFS is recommended when using VirtualBox [↩](#a3)