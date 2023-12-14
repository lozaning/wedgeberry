# wedgeberry
Wedgeberry is a single script that provides an interactive menu to configure a Raspberry Pi into a Wifi transparent proxy to support traffic inspection and tampering.

Currently the following can be configured via the `wedge-config` interactive menu:

- Wifi access point with DHCP 
- Mitmproxy as transparent proxy 
- Routing all outbound traffic via Wireguard VPN tunnel
- Forward TCP ports (and DNS) via the Tor network
- Forward TCP ports to external interception proxy (BurpSuite) 

`wedge-config.sh` will handle all the required package installs, `iptables` rules, `ip route` rules and systemd services for persistance (including mitmproxy).

The script was motivated by the Raspberry Pi `raspi-config` tool which provides an accessible way to configure a Pi. Here we provide an easy and quick way to configure a Pi into a Wifi access point that supports various traffic forwarding options along with common tooling for IoT / mobile device security research / testing.

![wedge-config](wedge.png)

# Installation

From a Raspberry Pi:
```
wget https://raw.githubusercontent.com/haxrob/wedgeberry/main/wedge-config.sh
sudo ./wedge-config.sh
```

Note, to build `wedge-config.sh` from this repository, run
```
make clean
make
sudo ./wedge-config.sh
```
Run with `-d` flag to write bash verbose output to logfile `wedge-debug.log` within the current working directory.

# Menu items

**Setup** - Peforms initial configuration (hostap, dhcp)
- **Automatic** - Installs with defaults (SSID, channel, wifi password, DHCP subnet)
- **Custom** - Custom Wifi network parameters

**Clients** - Lists Wifi stations connected that have a DHCP assigned address

**Connectivity** - Select outbound traffic path
- **Direct** - Default route out of selected interface
- **Wireguard** - Route via Wireguard interface. Can specify custom wireguard configuration or interactivly configure via menu options
- **TOR** - Forward specific TCP ports via Tor network
- **BurpSuite / External proxy** - Forward specific TCP ports to BurpSuite proxy running on external host
- **MITMProxy** - Forward specific portst o MITMProxy transparent proxy running on Pi

**Tools** - Install, configure or run useful toolls
- **MITMProxy** - Installs MITM proxy as a systemd service
- **Termshark** - Install or run termshark.io (cli based wireshark clone)

**Healthcheck** - Checks status of configuration and software services 

**Update** - Check and update script to latest version

**Uninstall** - Reverts configurations applied and optionally uninstalls packages

# Compatibility

Two interfaces are required - All Pi models that support Wifi should work out of the box except the Pi W. Here an additional interface card is required to be connected.

It is recommended to use [latest Raspberry Pi images](https://www.raspberrypi.com/software/operating-systems/). This software has only been tested on the Rasperry Pi image `Debian GNU/Linux 12 (bookworm)`.