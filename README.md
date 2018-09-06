# openvpn-conf-helper

### Setup OpenVPN
The official Ubuntu repository is lagging behind with the version of Openvpn server
So do the following:
```
curl -s https://swupdate.openvpn.net/repos/repo-public.gpg | sudo apt-key add
sudo vim /etc/apt/sources.list.d/openvpn-aptrepo.list
and add "deb http://build.openvpn.net/debian/openvpn/stable xenial main"
sudo apt-get update
sudo apt-get install openvpn
```
```
sudo adduser --system --shell /usr/sbin/nologin --no-create-home ovpn
sudo groupadd ovpn
sudo usermod -g ovpn ovpn
```
Start the script, navigate and input the required options to create configuration files for server and clients. This will create the certificates and all the required settings to setup a hardened openvpn server.

Copy the files in the resulted folder to /etc/openvpn/ and enable and start the server.
```
sudo systemctl enable openvpn@server
sudo systemctl start openvpn@server
```
Copy the client/s .ovpn files to your client/s.
Enjoy secured and fast internet communication!

### Supported platforms
Ubuntu 16.04 and up. Might work on others. Try and see.

### Useful links:
- https://wwwx.cs.unc.edu/~sparkst/howto/network_tuning.php
- https://community.openvpn.net/openvpn/ticket/461#comment:11
- https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage
- https://www.linode.com/docs/networking/vpn/set-up-a-hardened-openvpn-server/
- https://www.digitalocean.com/community/tutorials/how-to-set-up-an-openvpn-server-on-ubuntu-16-04

### TODO
- use ECDH instead of DH
