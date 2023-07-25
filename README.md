# WireGuard installer for Gaming / having public ip behind cgnat

**This project is a bash script that aims to setup a [WireGuard](https://www.wireguard.com/) VPN that is specified for PERSONAL gaming or torrenting use. It supports only ONE client!**

If you are looking for a common WireGuard install script that supports multi-client connections, i.e. multiple devices connect to the VPN at the same time, please visit [this repository](https://github.com/angristan/wireguard-install/) to continue.

The script **Port Forwards** the local port 1-65521 (also icmp) to the corresponding ports on the server side. These ports covered most of the ports used by any games. **Please make sure that there is no other application using these ports on the server, otherwise It will deafen any application that listens to these ports.** I highly suggest running this script on an new empty system. 

## The script will move ssh to port 65522 for not losing access to the server after installation.

The script supports both IPv4 and IPv6, but its preferred to use ipv4 as connection to the server.

## Gaming Improvement

For a better gaming experience, the server should be close to your living region and has a low ping value. You should ping the provider's looking glass datacenter IP first before purchasing a VPS. also look if the ip of the provider are in some blacklist that might impact your navigation.

## Requirements

Supported distributions:

- Ubuntu >= 16.04
- Debian = 10-11

## Usage

Download and execute the script. Answer the questions asked by the script and it will take care of the rest. For most VPS providers, you can just enter through all the questions.

```bash
wget https://raw.githubusercontent.com/Brazzo978/wg_gaming_installer/ipv6-public-subnet/wg-gaming-installer.sh
bash ./wg-gaming-installer.sh
```

It will install WireGuard (kernel module and tools) on the server, configure it, create a systemd service and a client configuration file.

## Stop / Restart / Uninstal

Run the script again will give you these options!


# Usage
List of know working vps provider :                                                        
-Hetzner Y  (routed ipv6 prefix can be delegated to client , so they will have a public ipv6 )       
-Linode Y            
-Aruba Y                        
-Vultr Y ( with bgp possibilities so you can import your ips )                      
-Gamehosting Y  (only kvm )                             
-Seflow Cloud Y                         
-Seflow VPS Y                               
-Ovh  Y                                        
