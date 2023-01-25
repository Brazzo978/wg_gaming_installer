# WireGuard installer for Forwarding a secondary public ipv4 from the vps to a remote wireguard client

**This project is a bash script that aims to setup a [WireGuard](https://www.wireguard.com/) tunnel that supports only ONE client!**



The script Ask you for the secondary ip that your vps has assigned and make a simple arp proxy that let the wireguard client use the public ip as the tunnel ipv4, giving a public ipv4 with all protocols / port open like the one used on the vps.


## Requirements

Supported distributions:

- Ubuntu >= 16.04
- Debian = 10-11

## Usage

Download and execute the script. Answer the questions asked by the script and it will take care of the rest. For most VPS providers, you can just enter through all the questions.

```bash
wget https://raw.githubusercontent.com/Brazzo978/wg_gaming_installer/Ip-Passtrough-pfsense/wg-gaming-installer.sh
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
