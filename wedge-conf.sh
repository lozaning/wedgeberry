#!/bin/bash
# generated Thu 14 Dec 08:38:03 GMT 2023

# MIT License
# 
# Copyright (c) 2023 HaxRob
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

DEBUG_LOG="./wedge-debug.log"

# configuration options. When run as sudo this will be in root's home directory
CONF_FILE="${HOME}/.config/wedge.conf"

# -d switch to write to debug log
if [[ $1 = "-d" ]]; then
   exec 5> $DEBUG_LOG 
   BASH_XTRACEFD="5"
   PS4='${LINENO}: '
   set -x
fi


# configuration parameters are reloaded 'from disk' each time a menu page is displayed
function reload_conf() {
   . $CONF_FILE
}

# config file already written before
if [ -e $CONF_FILE ]; then
   reload_conf
fi

################################################################################
# main_menu
################################################################################
function main_menu {
   while true; do
      reload_conf
      options=(
         "1 Setup" "Initial setup and configuration options"
         "2 Clients" "Display connected client information"
         "3 Connectivity" "Setup optional VPN, proxy or Tor network"
         "4 Tools" "Configure or run inspection tools"
         "5 Health check" "Check status of system components"
         "6 Update" "Update this tool to the latest version"
         "7 Uninstall" "Remove all configurations and software"
      )

      status=$(get_status_text)
      choice=$(menu "${status}" options "Finish")

      if [ $? -ne 0 ]; then
         exit
      fi

      case $choice in
         1\ *) ap_setup_menu;;
         2\ *) display_clients;;
         3\ *) tunnel_config_menu ;;
         4\ *) tools_menu;;
         5\ *) healthcheck ;;
         6\ *) check_updates ;;
         7\ *) uninstall ;;
      esac
   done
}

function is_not_setup() {
   # TODO
   return 0
   if [ $STATUS_STATE -ne 1 ]; then
      if yesno_box 8 "Initial setup has not been run. Would you like to run it now?"; then
         ap_setup_menu
         return 1
      fi
      msg_box 8 "Initial setup must be run before continuing"
      return 0
   fi
   msg_box 8 "returning 1"
   return 1
}

function tunnel_config_menu() {

   options=(
      "1 Direct" "Direct via network interface"
      "2 Wireguard" "Route all traffic via Wireguard VPN"
      "3 TOR" "Route all traffic via the TOR network"
      "4 BurpSuite / external proxy" "Forward specific ports to proxy"
      "5 MITMProxy" "Forward specific ports MITMproxy on Pi"
      "6 Back" "Return to previous menu"
   )

   choice=$(menu "Select tunnel configuration" options)
   if [ $? -ne 0 ]; then
      return
   fi

   case $choice in
      1\ *) direct_no_tunnel;;
      2\ *) conf_wireguard;;
      3\ *) conf_tor;;
      4\ *) conf_port_fwd;;
      5\ *) set_mitmproxy_iptables;;
      6\ *) return;;
   esac
}

function ap_setup_menu() {
   options=(
      "1 Automatic" "Use predefined defaults"
      "2 Custom" "Specify custom parameters"
   )
   choice=$(menu "Select setup type" options)
   if [ $? -ne 0 ]; then
      return
   fi
   case $choice in
      1\ *) USE_DEFAULTS=1; run_setup ;;
      2\ *) unset USE_DEFAULTS; run_setup;;
   esac
}

function tools_menu() {
   options=(
     "1 MITMProxy" ""
     "2 Termshark" "(wireshark-like)"
     "3 Back" "Return to previous menu"
   )
   choice=$(menu "Select software to install/configure" options)
   if [ $? -ne 0 ]; then
      return
   fi
   case $choice in
      1\ *) mitmproxy_setup;;
      2\ *) termshark_run;;
      3\ *) return;;
   esac
}



################################################################################
# conf_file_setup
################################################################################
function conf_file_setup {
   if [ ! -e "${HOME}/.config" ]; then
      mkdir "${HOME}/.config"
   fi
   if [ ! -e "$CONF_FILE" ]; then
      echo "STATUS_STATE=0" > $CONF_FILE
      echo "TUNNEL_TYPE=DIRECT" >> $CONF_FILE
   fi
}

################################################################################
# sets a configuration parameter, specified as an argument and also 'saves'
# it in the persistant configuration file
# returns 0
################################################################################
function set_conf_param() {
   param=$1
   value=$2
   declare "${param}"="${value}"
   sed -i "/${param}=/d" $CONF_FILE
   echo "${param}=${value}" >> $CONF_FILE
}

################################################################################
# Status text shown at top of main menu
# Shows wifi clients connected and traffic forward/routes/tunnels
################################################################################
function get_status_text() {
   local text=""
   if [ $STATUS_STATE -eq 0 ]; then
      text="\nStatus: Initial setup"
      if wireguard_is_iface_setup; then
         text+=" (Note: wireguard tunnel up)"
      fi
      echo "$text"
      return
   fi

   if [ $STATUS_STATE -eq 2 ]; then
      text="Status: Initial setup failed. Resolve issues and re-run setup"
      echo "$text"
      return
   fi

   if [ $MITMPROXY_ENABLED -ne 0 ]; then
      mitmproxy_text=" MITMProxy"
   fi

   text="\n       "

   station_count=$(connected_stations)
   if [ $station_count -gt 1 ]; then
      station_text="${station_count} connected clients"
   fi
   if  [ $station_count -eq 0 ]; then
      station_text="no connected clients"
   fi
   if [ $station_count -eq 1 ]; then
      station_text="1 connected client"
   fi

   text+="SSID: ${AP_SSID}, ${station_text}\n"
   text+="       "
   text+="${WLAN_IFACE} -> [pi${mitmproxy_text}] -> ${EXT_IFACE} -> "
   case $TUNNEL_TYPE in
      DIRECT) text+="Internet";;
      WIREGUARD) text+="Wireguard VPN"
      if ! wireguard_is_iface_setup; then
         text+="(DOWN)"
      fi
      ;;
      TOR) text+="TOR";;
      INLINE_PROXY) text+="$UPSTREAM_PROXY_HOST";;
   esac
   echo "$text"
}

function main() {
   check_root
   conf_file_setup
   main_menu
}



# TODO: Seperate functionality into each "module" file
function healthcheck() {
   fail_text="$1"
   pass_text="$2"

   issues=()
   if [ ! -f $IPTABLES_PERSIST_FILE ]; then
      issues+=( "iptables rules will not persist on reboot" )
   fi
   grep -q "net.ipv4.ip_forward*=*1" /etc/sysctl.conf
   if [ $? -ne 0 ]; then
      issues+=( "ip forwarding not enabled" )
   fi
   if [ ! -f "/etc/dhcpcd.conf" ]; then
      issues+=( "no dhcpcd configuration found" )
   fi

   if [ ! -f "/etc/dnsmasq.conf" ]; then
      issues+=( "no dnsmasq conf" )
   fi

   if [ ! -f "/etc/hostapd/hostapd.conf" ]; then
      issues+=( "no hostapd.conf" )
   fi

   if [ ! -f "/etc/default/hostapd" ]; then
      issues+=( "no /etc/default/hostapd" )
   fi

   missing_required_packages=()
   for package in "${REQUIRED_PACKAGES[@]}"; do
      if ! is_installed "$package"; then
         issues+=( "package '${package}' is not installed" )
         missing_required_packages+=( "$package" )
      fi
   done

   for service in "${REQUIRED_SERVICES[@]}"; do
      systemctl is-active --quiet "$service"
      if [ $? -ne 0 ]; then
         issues+=( "service '${service}' is not running" )
      fi
   done

   if [[ -z $TUNNEL_TYPE ]] && [[ $TUNNEL_TYPE = "WIREGUARD" ]]; then
      wg show | grep -q peer
      if [ $? -ne 0 ]; then
         issues+=( "Wireguard is configured to be used, but there is no peer up" )
      fi
      ip route show table 1000 | grep -q $WG_IFACE
      if [ $? -ne 0 ]; then
         issues+=( "Missing wireguard routing table" )
      fi
   fi

   if [[ -z $TUNNEL_TYPE ]] && [[ $TUNNEL_TYPE = "TOR" ]]; then
      systemctl is-active --quiet tor
      if [ $? -ne 0 ]; then
         issues+=( "TOR is configured to be used, but the service is not running" )
      fi
   fi

   if [[ -z $MITMWEB_SERVICE ]] && [[ $MITMWEB_SERVICE -eq 1 ]]; then
      if [[ $(systemctl is-active mitmweb.service) != "active" ]]; then
         issues+=( "mitmweb is configured as a service, but the service is not running" )
      fi
   fi

   if [ "${#issues}" -ne 0 ]; then
      if [ -z "$fail_text" ]; then
         text="The following problems were found:\n\n"
      else
         text="${fail_text}:\n\n"
      fi

      for issue in "${issues[@]}"; do
         text="${text}\n* ${issue}"
      done
      msg_box_scroll "$text"

      if [ "${#missing_required_packages}" -gt 0 ]; then
         msg_box 8 "Please (re)run setup to install missing (required) packages"
      fi
      return 1
   else
      if [ -z "$pass_text" ]; then
         msg_box 8 "Healthcheck passed all checks"
      else
         msg_box 8 "$pass_text"
      fi
   fi
   set_conf_param STATUS_STATE 1
   return 0
}

###############################################################################
# checks that two network interfaces exist by enumerating /sys/class/net
# RETURNS 1 on failure
################################################################################
function check_interface_count {
   
   # ignore loopback
   # TODO: ignore tunnel interfaces
   local count=$(ls /sys/class/net/ | grep -v lo | wc -l)
   if [ $count -lt 2 ]; then
      msg_box 8 "Two network interfaces are required. Only ${count} was detected.\n\
Please add an additional ethernet or wifi USB interface to the Pi"
      return 1
   fi
}
################################################################################
# obtains interface with default route for use in interfaces_list_menu to 
# display all interfaces with the default as the pre-selected
# sets EXT_IFACE
# returns 1 on failure
################################################################################
function set_outbound_interface() {
   default_iface=$(ip r | awk  '/default/ { print $5 }')
   EXT_IFACE=$(interfaces_list_menu "Select outbound interface for outbound network access" $default_iface)
   if [ $? -ne 0 ]; then
      return 1
   fi
   set_conf_param EXT_IFACE $EXT_IFACE
   return 0
}

################################################################################
# displays menu with network interfaces for selection that are wired
# ommits wlan, lo and wireguard interfaces
# returns: 0 on OK
#          1 on Cancel
# stdout:  selected interface name
################################################################################
function interfaces_list_menu() {
   local iface
   local ifaces=()

   # don't show loopback, wlan or vpn interfaces
   declare -A filter
   iface_filter=("lo" "${WLAN_IFACE}" "${WG_IFACE}")
   for i in "${iface_filter[@]}"; do
      filter[$i]=1
   done

   for dir in /sys/class/net/*; do
      if [ -d "$dir" ]; then
         iface=$(basename "$dir")

         # current interface is not in filter list
         if [[ ! ${filter[$iface]} ]]; then 
            ifaces+=($iface " " )
         fi
      fi
   done

   whiptail --title "$WHIP_TITLE" --menu "$1" 10 80 "${#ifaces[@]}" "${ifaces[@]}" 3>&1 1>&2 2>&3
   return $?
}

################################################################################
# lists wireless lan interfaces menu by enumerating /sys/class/net/*/wireless
# returns: 0 OK
#          1 Cancel
# stdout:  selected interface name
################################################################################
function select_wlan_interfaces() {
   local iface
   whip_args=()
   for dir in /sys/class/net/*/wireless; do
      if [ -d "$dir" ]; then
         iface="$(basename "$(dirname "$dir")")"
         whip_args+=( $iface " ")
      fi
  done
  whiptail --title "$WHIP_TITLE" --menu "$1" 10 80 "${#whip_args[@]}" "${whip_args[@]}" 3>&1 1>&2 2>&3
  return $?
}

################################################################################
# check_internet_connectivity
################################################################################
function check_internet_connectivity() {
   echo "checking connection"
   ping -q -c1 debian.org &>/dev/null
   if [ $? -ne 0 ]; then
      msg_box 8 "Unable to reach the Internet. Internet connectivity is required to install required packages"
      return 1
   fi
   return 0
}

function get_public_ip() {
   ipinfo=$(curl --silent https://ipinfo.io)
   formatted=$(echo "$ipinfo" | sed 's/, /\n/g' | tr -d '"{' | sed 's/:/: /g' | sed 's/^ //' | grep -v readme)
   msg_box 15 "$formatted"
}

################################################################################
# direct_no_tunnel
################################################################################
function direct_no_tunnel() {
   disable_egress_services 
   set_conf_param TUNNEL_TYPE DIRECT
   set_direct_iptables
   msg_box 8 "Direct connection (no tunnel) configured."
}

# iptables defaults
IPTABLES_PERSIST_FILE="/etc/network/if-pre-up.d/iptables"
IPTABLES_SAVE_FILE="/etc/iptables.up.conf"

################################################################################
# iptables configuration for nat / masq
# returns: 0
################################################################################
function set_direct_iptables() {
   iptables -t nat -F
   iptables -t nat -A POSTROUTING -o $EXT_IFACE -j MASQUERADE -m comment --comment WEDGE_TUNNEL_DIRECT
   save_iptables
}

################################################################################
# save iptables config to survive reboot 
# returns: 0
################################################################################
function save_iptables {
   iptables-save > $IPTABLES_SAVE_FILE
   if [ ! -f $IPTABLES_PERSIST_FILE ]; then
      echo "#!/bin/sh" > $IPTABLES_PERSIST_FILE
      echo "/sbin/iptables-restore < /etc/iptables.up.conf" >> $IPTABLES_PERSIST_FILE
      chmod +x $IPTABLES_PERSIST_FILE
   fi
}

function cleanup_iptables {
   iptables -F
   iptables -F -t nat
   
   rm -f $IPTABLES_PERSIST_FILE
   rm -f $IPTABLES_SAVE_FILE
}

WHIP_TITLE="Wedgeberry Pi Configuration Tool (wedge-config)"

################################################################################
########## // whiptail widgets #################################################
################################################################################
function input_box() {
   local text="$1"
   local default_value="$2"
   local custom_value="$3"
   if [ -n "$custom_value" ]; then
      default_value="$custom_value"
   fi
   whiptail --title "$WHIP_TITLE" --inputbox "$text" 10 80 "$default_value" 3>&1 1>&2 2>&3
}

function msg_box() {
   local height="$1"
   local text="$2"
   whiptail --title "$WHIP_TITLE" --msgbox "$text" $height 80
}

function yesno_box() {
   local lines="$1"
   local text="$2"
   #local lines=$(printf "%s" "$text" | wc -l)
   #lines=$(($lines+11))
   whiptail --title "${WHIP_TITLE}" --yesno "$text" $lines 80 3>&1 1>&2 2>&3
   return $?
}

function msg_box_scroll() {
   local tmp=$(mktemp)
   echo "$1" > $tmp
   whiptail --scrolltext --title "${WHIP_TITLE}" --textbox $tmp 20 80
   rm $tmp
}

function menu() {
   local -n opts="$2"
   local l="${#opts[@]}"
   local len=$(($l / 2))
   local cancel_text="$3"
   if [ -z "$cancel_text" ]; then
      cancel_text="Back"
   fi
   whiptail --title "${WHIP_TITLE}" --menu --cancel-button "$cancel_text" --ok-button Select "$1" 20 80 $len "${opts[@]}" 3>&1 1>&2 2>&3
   ret=$?
   return $ret
}
################################################################################
# validate subnet format
# params:   ip range with subnet (eg: 192.168.0.0/22)
# returns:  0 success
#           1 invalid subnet format
################################################################################
function is_invalid_net() {
   if [[ -z $1 ]]; then
      return 0
   fi
   if [ "$(ipcalc -n -b $1 | cut -d' ' -f1 | head -1)" != "INVALID" ]; then
      return 1
   fi
   return 0
}

function check_root() {
   if [ "$EUID" -ne 0 ]; then
      echo "Script must be run as root. Try sudo ${BASH_SOURCE}"
      exit
   fi
}

function get_arch() {
   arch=$(dpkg --print-architecture)
   echo "$arch"
}



REQUIRED_PACKAGES=(iptables ipcalc dnsmasq hostapd dhcpcd resolvconf)
OPTIONAL_PACKAGES=(tor wireguard termshark)

################################################################################
# check if package is installed on system. (lifted from raspi-conf)
# returns: 0 if packge is installed
#          1 if package is not installed 
################################################################################
is_installed() {
  if [ "$(dpkg -l "$1" 2> /dev/null | tail -n 1 | cut -d ' ' -f 1)" != "ii" ]; then
    return 1
  else
    return 0
  fi
}

################################################################################
# enumerate mandatory packages and install any that are missing
# returns: 0
################################################################################
function deps_install() {
   missing_packages=()
   apt_list=()
   for package in "${REQUIRED_PACKAGES[@]}"; do
      if ! is_installed $package; then
         missing_packages+=( "\n" "* ${package}" )
         apt_list+=( "${package}" )
      fi
   done
   if [ "${#missing_packages}" -ne 0 ]; then
      check_internet_connectivity
      if [ $? -ne 0 ]; then
         msg_box "No internet connectivity. This is required for package installation"
      fi
      size=$((${#apt_list} + 8))
      msg_box $size "The following packages will be installed:\n${missing_packages[*]}"
      check_if_apt_update
      apt install -y "${apt_list[@]}"
   fi

}

################################################################################
# calculate days between now and the last time 'apt-get' was run
# /var/catch/apt/pkgcache.bin MTIME seems to be a useful filename to check
# returns: 0
################################################################################
function days_apt_last_run() {
   now=$(date +'%s')
   apt_stat=$(stat --format='%Y' /var/cache/apt/pkgcache.bin)
   delta=$(($now-$apt_stat))
   echo $(($delta / 86400))
}


################################################################################
# prompt user if should run apt-get update. running this every time apt-get 
# install is invoked adds significant delay 
# returns: 0
################################################################################
function check_if_apt_update() {
   local update_threshold=10
   if (($(days_apt_last_run) > update_threshold));then
      if yesno_box 8 "'apt-get update' has not been run for ${update_threshold} days. Would you like to update?"; then
         apt-get update
      fi
   fi
}


REQUIRED_SERVICES=(dnsmasq hostapd dhcpcd)
# resolvconf required for wireguard
OPTIONAL_SERVICES=(tor resolvconf )

################################################################################
# disable tunnels or other connectivity 
# returns 0
################################################################################
function disable_egress_services() {

   # TODO: do we want to stop the mitmweb service here? Flushing iptables will
   # stop routing selected ports to mitmproxy

   # a hammer
   iptables -F
   iptables -F -t nat

   # tor
   if [[ $(systemctl is-active tor) = "active" ]]; then
      msg_box 8 "Disabling previously enabled tor service"
      systemctl disable --now tor 
   fi

   # wireguard
   wgservice="wg-quick@${WG_IFACE}.service"
   if [[ $(systemctl is-active $wgservice) = "active" ]]; then
      msg_box 8 "Disabling previously enabled wireguard interface service"
      systemctl disable --now $wgservice
   fi


}
################################################################################
# start mandatory services
# returns 0 
################################################################################
function start_services {

   # hostapd
   if [[ $(systemctl is-enabled hostapd.service) != "enabled" ]]; then
      systemctl unmask hostapd.service
      systemctl enable --now hostapd.service
   fi

   # resolved TODO: (is this only required for wireguard)
   if [[ $(systemctl is-active systemd-resolved) = "active" ]]; then
      echo "stopping systemd-resolved"
      systemctl stop systemd-resolved
      systemctl mask systemd-resolved
   fi 

   # dnsmasq
   systemctl restart dnsmasq

   # dhcpcd
   systemctl restart dhcpcd
}

################################################################################
# stops both required services and any optional service that is active
# these are defined in the arrays REQUIRED_SERVICES and OPTIONAL_SERVICES at 
# the start of the script
################################################################################
function stop_services() {
   all_services=( "${REQUIRED_SERVICES[@]}" "${OPTIONAL_SERVICES[@]}" )
   for service in "${all_services[@]}"; do
      if [[ $(systemctl is-active "$service") = "active" ]];then 

         # disabling and stopping dhcpcd will kill the current session, so let's not stop this
         if [[ $service != "dhcpcd" ]]; then
            systemctl disable --now $service
         fi
      fi
   done

}

################################################################################
# Initial setup procedure
################################################################################
function run_setup() {
   if [ $STATUS_STATE -eq 1 ]; then
      yesno_box 8 "AP mode is already setup. Continuing will override existing configuration. Continue?"
      if [ $? -eq 1 ]; then
         return 1
      fi
   fi
   setup_items
   case $? in
      1) msg_box 8 "Setup cancelled, please re-run setup or run health check";;
      2) msg_box 8 "Setup failed, please resolve issues or run health check";;
   esac
}

function setup_items() {
   check_interface_count
   if [ $? -ne 0 ]; then
      return 2
   fi
   set_conf_param STATUS_STATE 0
   set_conf_param MITMPROXY_ENABLED 0
   set_conf_param TUNNEL_TYPE DIRECT
   disable_egress_services
   set_wifi_network
   if [ $? -eq 1 ]; then
      return 1
   fi
   set_outbound_interface
   if [ $? -ne 0 ]; then
      return 1
   fi
   setup_hostap
   if [ $? -ne 0 ]; then
      return 1
   fi
   confirm_settings
   if [ $? -ne 0 ]; then
      return
   fi
   deps_install
   write_hostap_conf
   set_dhcpcd
   conf_dnsmasq
   set_ipfwd

   # isues if wg is down

   set_conf_param TUNNEL_TYPE DIRECT
   set_direct_iptables
   start_services

   healthcheck "Setup not complete, issues were found" "Setup complete!"
   if [ $? -ne 0 ]; then
      set_conf_param STATUS_STATE 2
      return
   fi
   set_conf_param STATUS_STATE 1
}

################################################################################
# set_ipfw
# returns: 0
################################################################################
function set_ipfwd() {
   echo "Setting ipv4.ip_forward"
   sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
   echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
   sysctl -p
}

function cleanup_sysctl() {
   sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
   sysctl -p
}
function uninstall() {
   if ! yesno_box 8 "Remove all configuration files?"; then
      return
   fi

   rm "$CONF_FILE"
   reload_conf

   cleanup_iptables
   cleanup_sysctl
   cleanup_dhcpcd
   cleanup_hostapd
   cleanup_dnsmasq
   cleanup_hostapd
   cleanup_wireguard

   stop_services

   if [ -z "$MITM_SERVICE" ] && [ "$MITMWEB_SERVICE" -eq 1 ]; then
      remove_mitmweb_service
   fi

   set_conf_param STATUS_STATE 0
   if ! yesno_box 8 "Remove all installed software packages?"; then
      return
   fi

   for package in "${REQUIRED_PACKAGES[@]}"; do
      apt-get -y remove "$package"
   done

   for package in "${OPTIONAL_PACKAGES[@]}"; do
      apt-get -y remove "$package"
   done

   if yesno_box 8 "Recommended to reboot. Continue?";then
      /usr/sbin/reboot
   fi

}

# wifi defaults
DEFAULT_WIFI_CHANNEL=11
DEFAULT_SSID=wedge-ap
DEFAULT_WIFI_PASSWORD="012345678"

################################################################################
# present a list of country codes in a menu
# returns: 0 OK
#          1 Cancel
# stdout:  selected country code 
################################################################################
function wifi_country() {
   value=$(sed '/^#/d' /usr/share/zoneinfo/iso3166.tab | tr '\t\n' '/')
   oIFS="$IFS"
   IFS="/"
   REGDOMAIN=$(whiptail --menu "Select the country in which the Pi is to be used" 20 60 10 ${value} 3>&1 1>&2 2>&3)
   ret=$?
   IFS="$oIFS"
   echo "$REGDOMAIN"
   return $ret
}

################################################################################
# create hostap configuration file
# if country code is not prior set (via raspi-config), present oppertunity to
# choose here as this value must be defined in the hostap configuraiton.
# returns: 1 on any cancel
# sets: conf AP_SSID
#       hostap_contents
# TODO: support more then WPA2
# TODO: fix no password / public
################################################################################
function setup_hostap() {
   regdomain="$(iw reg get | sed -n "0,/country/s/^country \(.\+\):.*$/\1/p")"
   if [ -z $regdomain ] || [ $regdomain = "00" ]; then
      regdomain=$(wifi_country)
      if [ $? -ne 0 ]; then
        msg_box "Country must be chosen. You can also set this in rasp-config. Aborting"
        return 1
      fi
      raspi-config nonint do_wifi_country "$regdomain"
   fi
   hostap_conf="/etc/hostapd/hostapd.conf"

   if [[ ! $USE_DEFAULTS ]]; then

      # access point name
      while [[ -z "$AP_SSID" ]]; do
         AP_SSID=$(input_box "SSID" $DEFAULT_SSID)
         if [ $? -ne 0 ]; then
            return 1
         fi
         if [ -z $AP_SSID ]; then
            msg_box "Enter valid SSID"
         fi
      done
      set_conf_param AP_SSID $AP_SSID
      
      # radio channel
      AP_CHANNEL=$(input_box "channel" $DEFAULT_WIFI_CHANNEL)
      if [ $? -ne 0 ]; then
         return 1
      fi

      if [[ -z $AP_CHANNEL ]]; then
         AP_CHANNEL=$DEFAULT_WIFI_CHANNEL
      fi

      # access point password
      AP_PASSWORD=$(input_box "Wifi password. Leave empty for no password (public wifi)")
      if [ $? -ne -0 ]; then
         return 1
      fi
      
      # allow 0 or 8 or more characters. 0 means public wifi
      len=${#AP_PASSWORD}
      while [[ $len -ne 0 ]] && [[ $len -le 7 ]]; do
         msg_box "Password must be longer or equal to 8 characters"
         AP_PASSWORD=$(input_box "Wifi password. Empty if none")
         if [ $? -ne 0 ]; then
            return 1
         fi
         len=${#AP_PASSWORD}
      done
   else
      AP_SSID=$DEFAULT_SSID
      set_conf_param AP_SSID $AP_SSID
      AP_CHANNEL=$DEFAULT_WIFI_CHANNEL
      AP_PASSWORD=$DEFAULT_WIFI_PASSWORD
   fi

   hostap_contents=(
      "interface=${WLAN_IFACE}"
      "driver=nl80211"
      "ssid=${AP_SSID}"
      "country_code=${regdomain}"
      "hw_mode=g"
      "channel=${AP_CHANNEL}"
      "macaddr_acl=0"
      "auth_algs=1"
      "wmm_enabled=0"
   )

   # TODO: fix public wifi
   if [[ -n $AP_PASSWORD ]]; then
      hostap_contents+=(
         "wpa=2"
         "wpa_passphrase=${AP_PASSWORD}"
         "wpa_key_mgmt=WPA-PSK"
         "wpa_pairwise=TKIP"
         "rsn_pairwise=CCMP"
      )
   fi
}

################################################################################
# configure wifi parameters
# sets:    conf WLAN_IFACE
# returns: 0 on success
#          1 if cancel selected
################################################################################
function set_wifi_network() {

   WLAN_IFACE=$(select_wlan_interfaces "Select Wifi access point interface")
   if [ $? -ne 0 ]; then
      return 1
   fi
   set_conf_param WLAN_IFACE $WLAN_IFACE
   if [ $USE_DEFAULTS ]; then
      AP_ADDR="10.10.0.1"
      set_conf_param AP_ADDR $AP_ADDR
      WIFI_NET="10.10.0.0/24"
      WIFI_NET_HOST_MAX="10.10.0.254"
      WIFI_NET_MASK="255.255.255.0"
      WLAN_STATIC_ADDR="10.10.0.1/24"
      return 0
   fi

   while is_invalid_net $WIFI_NET ; do
      WIFI_NET=$(input_box "Wifi network" "10.10.0.0/24")
      if is_invalid_net "$WIFI_NET"; then
         msg_box 8 "Enter valid network"
      fi
   done
   ipcalc=$(ipcalc -n -b $WIFI_NET)
   AP_ADDR=$(echo "$ipcalc" | grep HostMin | awk '{print $2}')
   set_conf_param AP_ADDR $AP_ADDR
   WIFI_NET_HOST_MAX=$(echo "$ipcalc" | grep HostMax | awk '{print $2}')
   WIFI_NET_MASK=$(echo "$ipcalc" | grep Netmask | awk '{print $2}')
   subnet_bits=$(echo $WIFI_NET | cut -d'/' -f2)
   WLAN_STATIC_ADDR="${AP_ADDR}/${subnet_bits}"
}
################################################################################
# write hostap_contents to the hostapd configuration file(s)
# returns: 0
################################################################################
function write_hostap_conf() {
   printf '%s\n' "${hostap_contents[@]}" | sed '/^$/d' > $hostap_conf

   # delete (prevent duplicate lines)
   sed -i '/^DAEMON_CONF/d' /etc/default/hostapd
   echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
}

################################################################################
# confirm wifi ap settings
# returns: 0 Ok
#        : 1 Cancel
################################################################################
function confirm_settings {
   ap_password_text="$AP_PASSWORD"
   if [[ -z $AP_PASSWORD ]]; then
      ap_password_text="none (public)"
   fi

   local text=(
                "=========================================="
                "Wifi access point interface: ${WLAN_IFACE}"
                "Outbound traffic interface : ${EXT_IFACE}"
                "Wifi internal network      : ${WIFI_NET}"
                "Access point name          : ${AP_SSID}"
                "Access point password      : ${ap_password_text}"
                "Access point channel       : ${AP_CHANNEL}"
                "Country                    : ${regdomain}"
                "=========================================="
               )
   local text2=$(printf '%s\n' "${text[@]}")
   if yesno_box 20 "The following will be configured:\n\n${text2}\n\nContinue?"; then
      return 0
   else
      return 1
   fi
}

################################################################################
# get number of connected wlan clients
# returns: 0
# stdout:  integer of number of connections
################################################################################
function connected_stations() {
   count=$(iw dev $WLAN_IFACE station dump | grep connected | wc -l)
   echo "$count"
}

################################################################################
# display connected wifi client details
# these are wlan stations that have an IP address allocated
# returns: 0
################################################################################
function display_clients() {
   leases_file="/var/lib/misc/dnsmasq.leases"
   declare -A clients
   oIFS="$IFS"
   IFS=$'\n'
   for station in $(iw dev wlan0 station dump | egrep "Station|connected" | paste -sd ' \n' | tr -d '\t'); do
      mac=$(echo $station | cut -d' ' -f2)
      time=$(echo $station | cut -d' ' -f5-)
      clients["$mac"]="$time"
   done
   if [ ${#clients[@]} -eq 0 ]; then
      msg_box 8 "No wifi stations connected"
      return
   fi
   IFS="$oIFS"
   lines=""
   
   # TODO: what is difference between mac1 and mac2?
   while read -r ts mac1 ip name mac2; do
      if [[ ${clients["$mac1"]} ]]; then
         t=${clients["$mac1"]}
         clients["$mac1"]="$ip $t [$name]"
      fi
   done < $leases_file
   for a in "${!clients[@]}"; do
     lines+="${a} ${clients[$a]}\n"
   done
   msg_box_scroll "Connected Wifi clients with leased IP:\n\n$lines"
}

function cleanup_hostapd() {
   rm -f /etc/default/hostapd
   rm -f /etc/hostapd/hostapd.conf
}
################################################################################
# writes dhcpcd configuration
# returns: 0
################################################################################
function set_dhcpcd() {

   wlan_contents=(
      "interface ${WLAN_IFACE}"
      "static ip_address=${WLAN_STATIC_ADDR}"
      "nohook wpa_supplicant"
   )
   lines=$(printf '%s\n' "${wlan_contents[@]}" | sed '/^$/d')

   # replace everything under "interface <wlan interface>" until blank line
   # TODO: I don't think this is the best approach, but we don't want to 
   # blast away any existing config. need to evaluate this furter.
   
   sed -i "/interface ${WLAN_IFACE}/,/^$/d" /etc/dhcpcd.conf
   echo "$lines" >> /etc/dhcpcd.conf

   # different approach (not used), find line number if existing config and then delete
   # from there

   #lineno=$(grep -n "interface wlan0" /etc/dhcpcd.conf | cut -d: -f1)
   #if [ $? -ne 0 ]; then
   #   echo "$lines" >> /etc/dhcpcd.conf
   #   return
   #fi

   #edit from line number
   #sed "$lineno,$((lineno+2))s/static ip_address=.*/static ip_address=$host_min/g" /etc/dhcpcd.conf
}

function cleanup_dhcpcd() {
   rm -f /etc/dhcpcd.conf
   
   # note service will be stopped from stop_services later
}
DNS_LOG_FILE="${HOME}/wedge-dns.log"

################################################################################
# configure dnsmasq needed to issue IP addresses to wlan clients
# returns: 0
################################################################################
function conf_dnsmasq() {
   dnsmasq_conf="/etc/dnsmasq.conf"

   last_octet=$(echo $AP_ADDR | cut -d'.' -f 4)
   dhcp_start_addr="$(echo $AP_ADDR | cut -d. -f1,2,3).$((last_octet+1))"

   dnsmasq_contents=(
      "interface=${WLAN_IFACE}"
      "listen-address=${AP_ADDR}"
      "dhcp-range=${dhcp_start_addr},${WIFI_NET_HOST_MAX},${WIFI_NET_MASK},24h"
      "bind-dynamic"
      "domain-needed"
      "bogus-priv"
      "log-queries"
      "log-facility=${DNS_LOG_FILE}"
   )

   printf '%s\n' "${dnsmasq_contents[@]}" | sed '/^$/d' > $dnsmasq_conf

}

function cleanup_dnsmasq() {
   rm -f /etc/dnsmasq.conf
}
function mitmproxy_setup() {

   options=()
   
   user=$(who am i | awk '{print $1}')
   sudo -u $user pipx list 2>/dev/null | grep -q mitmproxy
   if [ $? -eq 0 ] || [ $MITMWEB_SERVICE -eq 1 ] ; then 
      if [ $(iptables -L -t nat | grep -q MITMPROXY)$? -ne 0 ]; then
         options+=( "1 Enable" "Enable port forwarding to MITMproxy" )
      else
         options+=( "1 Disable" "Disable forwarding to MITMProxy" )
      fi
      options+=( "2 Uninstall" "Remove MITMProxy packages" )
   else
      options+=( "1 Install" "Install MITMProxy" )
   fi

   choice=$(menu "Select options configure" options)
   if [ $? -ne 0 ]; then
      return
   fi
   case $choice in
      1\ Enable) set_mitmproxy_iptables;;
      1\ Disable) unset_mitmproxy_iptables;;
      1\ Install) mitmproxy_install;;
      2\ Uninstall) mitmproxy_uninstall;;
   esac

}

################################################################################
# set ports to redirect to mitmproxy service
# prompts port numbers in comma-seperated format, e.g 80,443
# sets conf MITMPROXY_ENABLED
# returns 0
################################################################################
function set_mitmproxy_iptables() {
   valid_input=1
   
   # validate first
   while [ $valid_input -eq 1 ]; do
      ports=$(input_box "Enter ports to forward (seperated by a ,)" "80,443")
      if [ $? -ne 0 ]; then
         return 1
      fi
      for port in ${ports//,/ }; do
         if ! [[ $port =~ ^[0-9]+$ ]]; then
            msg_box 8 "Invalid port number: $port"
            valid_input=1
         else
            valid_input=0
         fi
      done
   done
   set_conf_param MITMPROXY_ENABLED 1
   for port in ${ports//,/ }; do
      iptables -t nat -A PREROUTING -i $WLAN_IFACE -p tcp --dport $port -j  REDIRECT --to-port 8080 -m comment --comment WEDGE_MITMPROXY
      iptables -t nat -A PREROUTING -i $WLAN_IFACE -p tcp --dport $port -j REDIRECT --to-port 8080 -m comment --comment WEDGE_MITMPROXY
   done

   # mitmproxy documentation recommends this
   sysctl -w net.ipv4.conf.all.send_redirects=0
   sysctl -p
}

################################################################################
# remove iptables rules related to mitmproxy
# this is done by grepping out marker comments 
# sets: conf MITMPROXY_ENABLED 
# returns: 0
################################################################################
function unset_mitmproxy_iptables() {
   iptables-save | grep -v MITMPROXY | iptables-restore
   set_conf_param MITMPROXY_ENABLED 0
   return
}

function mitmproxy_install() {
   if ! is_installed pipx; then
      msg_box 8 "pipx is required to install mitmproxy - will install"
      sudo apt update
      apt-get -y install pipx
   fi

   if yesno_box 8 "Would you like to install mitmweb as a system service? Selecting yes will install mitmproxy into /opt/mitmproxy"; then
      mitmweb_install_service
      return
   fi
   # as script is being run as sudo, get the user that invoked sudo, otherwise everything
   # will be installed under /root
   user=$(who am i | awk '{print $1}')

   sudo -u $user pipx list | grep -q mitmproxy
   if [ $? -ne 0 ]; then
      msg_box 8 "mitmproxy will be installed user '${user}'"
      sudo -u $user pipx install mitmproxy
      sudo -u $user pipx ensurepath
   fi
}

function mitmproxy_uninstall() {
   user=$(who am i | awk '{print $1}')
   sudo -u $user pipx uninstall mitmproxy
   set_conf_param MITMPROXY_ENABLED 0 
   unset_mitmproxy_iptables
}

function mitmweb_install_service() {
   mkdir /opt/mitmproxy
   addgroup --system mitmproxy
   adduser --system --home /opt/mitmproxy --shell /usr/sbin/nologin --no-create-home --gecos 'mitmproxy' --ingroup mitmproxy --disabled-login --disabled-password mitmproxy
   chown -R mitmproxy:mitmproxy /opt/mitmproxy
   PIPX_HOME=/opt/mitmproxy sudo -E pipx install mitmproxy
   
   mitmweb_svc_path="/etc/systemd/system/mitmweb.service"
   mitmweb_listen_addr=$(ip -f inet addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
   # https://gist.github.com/avoidik/84ba17cc47987785cd7e5fe1b1aee603
   if [[ $(systemctl is-active mitmweb.service) = "active" ]]; then
      systemctl stop mitmweb.service
   fi
   mitmweb_svc_contents=(
      "[Unit]"
      "Description=mitmweb service"
      "After=network-online.target"
      "[Service]"
      "Type=simple"
      "User=mitmproxy"
      "Group=mitmproxy"
      "ExecStart=/opt/mitmproxy/venvs/mitmproxy/bin/mitmweb --mode transparent --showhost --no-web-open-browser --web-host ${mitmweb_listen_addr}"
      "Restart=on-failure"
      "RestartSec=10"
      "LimitNOFILE=65535"
      "LimitNPROC=4096"
      "PrivateTmp=true"
      "PrivateDevices=true"
      "ProtectHome=true"
      "ProtectSystem=strict"
      "NoNewPrivileges=true"
      "DevicePolicy=closed"
      "ProtectControlGroups=yes"
      "ProtectKernelModules=yes"
      "ProtectKernelTunables=yes"
      "RestrictNamespaces=yes"
      "RestrictRealtime=yes"
      "RestrictSUIDSGID=yes"
      "LockPersonality=yes"
      "WorkingDirectory=/opt/mitmproxy"
      "ReadOnlyDirectories=/"
      "ReadWriteDirectories=/opt/mitmproxy"
      "[Install]"
      "WantedBy=multi-user.target"
   )

   printf '%s\n' "${mitmweb_svc_contents[@]}" | sed '/^$/d' > $mitmweb_svc_path
   systemctl daemon-reload
   systemctl enable mitmweb.service
   systemctl start mitmweb.service
   if [ $? -ne 0 ]; then
      msg_box 8 "There was an error starting mitmweb systemd service. See journalctl -u mitmweb.service"
      return 1
   fi
   set_conf_param MITMWEB_SERVICE 1 
   msg_box 8 "mitmweb can be accessed on http://${mitmweb_listen_addr}:8081"
}

function remove_mitmweb_service() {
   systemctl stop mitmweb.service
   rm /etc/systemd/system/mitmproxy.service
   systemctl daemon-reload
   set_conf_param MITMWEB_SERVICE 0
}
function conf_port_fwd() {
   valid_input=1
   desthost=$(input_box "Enter proxy host and port (e.g. 1.2.3.4:8080)" "127.0.0.1:8080" $UPSTREAM_PROXY_HOST)
   if [ $? -ne 0 ]; then
      return 1
   fi
   while [ $valid_input -eq 1 ]; do
      ports=$(input_box "Enter ports to forward (seperated by a ,)" "80,443")
      if [ $? -ne 0 ]; then
         return 1
      fi
      for port in ${ports//,/ }; do
         if ! [[ $port =~ ^[0-9]+$ ]]; then
            msg_box 8 "Invalid port number: $port"
            valid_input=1
         else
            valid_input=0
         fi
      done
   done
   msg_box 12 "Selected ports will be forwarded to ${desthost}.\nNote in BurpSuite you must select 'Support invisible proxying' under 'Request handling' in the listening proxy settings"

   set_conf_param UPSTREAM_PROXY_HOST "$desthost"
   set_conf_param TUNNEL_TYPE INLINE_PROXY

   disable_egress_services
   iptables -t nat -A POSTROUTING -o $EXT_IFACE -j MASQUERADE
   for port in ${ports//,/ }; do
      iptables -t nat -A PREROUTING -i $WLAN_IFACE -p tcp --dport $port -j DNAT --to-destination $desthost
   done

}
function termshark_run() {
    termshark_check_install
    msg_box 8 "termshark will now listen on ${WLAN_IFACE}"
    termshark -i $WLAN_IFACE
}
function termshark_check_install() {
    if ! is_installed "termshark"; then
        if yesno_box 8 "Termshark is not installed. Install now?"; then
            check_if_apt_update
            apt install -y termshark
        fi
    fi
}

################################################################################
# redirect dns and tcp flows to tor services
# returns 0
################################################################################
function set_tor_iptables() {
   iptables -F
   iptables -t nat -F
   iptables -t nat -A PREROUTING -i $WLAN_IFACE -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment WEDGE_TUNNEL_TOR
   iptables -t nat -A PREROUTING -i $WLAN_IFACE -p tcp --syn -j REDIRECT --to-ports 9040 -m comment --comment WEDGE_TUNNEL_TOR
}

################################################################################
# write torrc file
# returns: 0
################################################################################
function conf_torrc() {
   torrc_contents=(
      "Log notice file /var/log/tor/notices.log"
      "VirtualAddrNetwork 10.192.0.0/10"
      "AutomapHostsOnResolve 1"
      "TransPort ${AP_ADDR}:9040"
      "DNSPort ${AP_ADDR}:53"
   )
   printf '%s\n' "${torrc_contents[@]}" | sed '/^$/d' > /etc/tor/torrc
   systemctl restart tor
}

################################################################################
# conf_tor
################################################################################
function conf_tor() {
   is_not_setup
   if [ $? -ne 0 ]; then
      return
   fi
   disable_egress_services
   if ! is_installed tor; then
      check_internet_connectivity
      if [ $? -ne 0 ]; then
         return $?
      fi
      if ! is_installed tor; then
         msg_box 8 "tor will now be be installed"
         apt-get install -y tor
      fi
   fi
   systemctl enable --now tor
   set_conf_param STATUS_STATE 0
   conf_torrc
   set_tor_iptables
   set_conf_param TUNNEL_TYPE TOR

   # give some time to bootstrap, say 10 seconds
   loop=0
   {
   while [ $loop -ne 100 ]; do
      loop=$(($loop+20))
      echo $loop
      sleep 2
     done
   } | whiptail --title "$WHIP_TITLE" --gauge "Waiting for tor circuit to establish..." 20 80 0

   check_tor_connectivity
   if [ $? -eq 0 ]; then
      msg_box 8 "TOR configured successfully"
   else
      msg_box 8 "TOR configured but there was an issue connecting to the TOR network"
   fi

   # despite to network conecitivty issues, still set the state as setup
   set_conf_param STATUS_STATE 1
}

################################################################################
# check_tor_connectivity
################################################################################
function check_tor_connectivity() {
   retries=0
   success=0
   while [ $retries -le 4 ] && [ $success -ne 1 ]; do
      check_req=$(curl -q -x socks5h://127.0.0.1:9050  https://check.torproject.org/api/ip)
      echo "$check_req" | grep -q 'IsTor":true'
      if [ $? -ne 0 ] && [ $success -ne 1 ]; then
         retries=$(($retries+1))
      else
         success=1
      fi
   done
   if [ $success -eq 0 ]; then
      return 1
   fi
   return 0
}
# wireguard defaults
WG_IFACE="wg-wedge"
WG_CONF_PATH="/etc/wireguard/${WG_IFACE}.conf"
WG_ROUTE_TABLE=1000

################################################################################
# set a default route for traffic to be sent to the wireguard next hop
# here this is appended to the PostUp directive in the wireguard configuration
# to survive reboot
# TODO: consider if these routes should be placed somewhere else
# returns: 0
################################################################################
function set_wireguard_route() {
   wg_conf="/etc/wireguard/${WG_IFACE}.conf"
   next_hop=$(grep Address /etc/wireguard/${WG_IFACE}.conf | cut -d' ' -f3 | cut -d'/' -f1)
   L1="ip r add default via $next_hop dev $WG_IFACE table $WG_ROUTE_TABLE"
   L2="ip rule add iif $WLAN_IFACE lookup $WG_ROUTE_TABLE"

   $L1
   $L2

   sed -i '/PostUp/d' $wg_conf
   sed -i "/Interface/a PostUp=${L2}" $wg_conf
   sed -i "/Interface/a PostUp=${L1}" $wg_conf

}

################################################################################
# iptables configuration for wireguard
# all traffic originating from WLAN inteface forwarded into the wireguard 
# interface
################################################################################
function set_wireguard_iptables() {
   iptables -F
   iptables -t nat -A POSTROUTING -o $WG_IFACE -j MASQUERADE -m comment --comment WEDGE_TUNNEL_WIREGUARD
   iptables -A FORWARD -i $WLAN_IFACE -o $WG_IFACE -j ACCEPT -m comment --comment WEDGE_TUNNEL_WIREGUARD
   iptables -A FORWARD -i $WG_IFACE -o $WLAN_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT -m comment --comment WEDGE_TUNNEL_WIREGUARD
   save_iptables
}

################################################################################
# conf_wireguard
################################################################################
function conf_wireguard() {
   if ! is_not_setup; then
      return
   fi
   if [ $? -ne 0 ]; then
      return
   fi
   
   disable_egress_services
   if ! is_installed wireguard; then
      check_internet_connectivity
      if [ $? -ne 0 ]; then
         return $?
      fi

      # will install wireguard-tools as part of wireguard package
      if ! is_installed wireguard; then
         if yesno_box 8 "Wireguard software is not installed. Install?"; then
            apt-get install -y wireguard resolvconf
         else
            msg_box 8 "Wireguard must be installed before continuing"
            return 1
         fi
      fi
   fi

   if [ $STATUS_STATE -ne 1 ]; then
      msg_box 8 "Initial setup not complete, refusing to setup wireguard tunnel"
      return 1
   fi

   options=(
      "1" "Use existing wireguard configuration file"
      "2" "Generate client wireguard configuration"
      "3" "Go back"
   )

   choice=$(menu "Select an option" options)
   if [ $? -ne 0 ]; then
      return 1
   fi

   case $choice in
         1) add_wireguard_conf;;
         2) interactive_wireguard_conf;;
         3) return;;
   esac
   if [ -f "$WG_CONF_PATH" ]; then
      healthcheck silent
      if [ $? -eq 1 ]; then
         msg_box 8 "Note: Health check failed."
      fi

      wireguard_up
      set_wireguard_iptables
      set_wireguard_route
      systemctl enable wg-quick@$WG_IFACE.service
   else
      msg_box 8  "You must add the wireguard configuration to the file ${WG_CONF_PATH} after setup"
   fi

}

################################################################################
# add_wireguard_conf
################################################################################
function add_wireguard_conf() {
   if yesno_box 8 "A text editor will be opened to add the wireguard configuration. Continue?"; then
      if [ ! -f $WG_CONF_PATH ]; then
         echo "# wg-configuration here\n" > $WG_CONF_PATH
      fi
      nano $WG_CONF_PATH
   fi
}

################################################################################
# interactive_wireguard_conf
################################################################################
function  interactive_wireguard_conf() {

   info_msg="\
   You will need the following details before continuing:

     * Local wireguard interface address
     * DNS server
     * Remote wireguard IP address
     * Remote wireguard public key

     Continue?"

   if ! yesno_box 14 "$info_msg"; then
      return
   fi

   private_key=$(wg genkey)
   public_key=$(echo $private_key | wg pubkey)

   address=$(input_box "Local tunnel address" "192.168.0.1")
   dns=$(input_box "dns server" "1.1.1.1")
   endpoint=$(input_box "Remote server address" "")
   svr_public_key=$(input_box "Remote server public key" "")

   wg_conf_contents=(
      "[Interface]"
      "PrivateKey = ${private_key}"
      "Address = ${address}/32"
      "DNS = ${dns}"
      ""
      "[Peer]"
      "PublicKey = ${svr_public_key}"
      "AllowedIPs = 0.0.0.0/0"
      "Endpoint = ${endpoint}"
   )
   printf '%s\n' "${wg_conf_contents[@]}" | sed '/^$/d' > $WG_CONF_PATH

   echo "$public_key" > "${HOME}/wg-pubkey.txt"
   info_msg="The public key of this wireguard endpoint is:\n${public_key}\n
   This key is required to be configured in the remote wireguard endpoint.

   A copy has been saved to '${HOME}/wg-pubkey.txt'"
   msg_box 20 "$info_msg"

}

################################################################################
# wireguard_up
################################################################################
function wireguard_up {
   set_conf_param TUNNEL_TYPE WIREGUARD
   if wireguard_is_iface_setup; then
      wg-quick down $WG_IFACE
   fi
   output=$(wg-quick up $WG_IFACE 2>&1)
   if [[ $output =~ .*error.* ]]; then
      msg_box_scroll "error:\n${output}"
      if yesno_box 8 "Configure again?"; then
         conf_wireguard
      fi
   fi
}

function wireguard_is_iface_setup() {
   # if interface is not configured, non zero return code
   wg show $WG_IFACE > /dev/null 2>&1
   return $?
}

function cleanup_wireguard() {
   wg-quick down $WG_IFACE
   ip route flush table $WG_ROUTE_TABLE 
   systemctl disable wg-quick@$WG_IFACE.service
}
# final bash script is generated via Makefile. Inform user if they attempt to run wrong script
if ! type -t healthcheck > /dev/null; then
   echo "Required functions undefined. Please run generated wedge-conf.sh, e.g. 'make; ./wedge-conf.sh'"
   exit
fi

main