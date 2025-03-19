#!/bin/bash

# WiFi Adapter Full Reset Script
# Resets all wireless adapters, properly handling monitor mode interfaces
# and recreating base interfaces

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try 'sudo $0'"
    exit 1
fi

# Check for aircrack-ng suite availability
HAS_AIRCRACK=0
if command -v airmon-ng &> /dev/null; then
    HAS_AIRCRACK=1
    echo "Aircrack-ng suite detected, will use it for monitor mode interfaces"
fi

# Find all wireless interfaces, including those with "mon" suffix
WIRELESS_INTERFACES=$(iw dev | grep Interface | awk '{print $2}')

# Add some additional checks to capture monitor interfaces that might be missed
MON_INTERFACES=$(ip link show | grep -o "[a-zA-Z0-9]*mon[0-9]*" | sort | uniq)

# Combine and deduplicate interfaces
WIRELESS_INTERFACES=$(echo "$WIRELESS_INTERFACES $MON_INTERFACES" | tr ' ' '\n' | sort | uniq)

if [ -z "$WIRELESS_INTERFACES" ]; then
    echo "No wireless interfaces found."
    exit 1
fi

echo "Found the following wireless interfaces:"
echo "$WIRELESS_INTERFACES"
echo "Starting reset process..."

# Process each wireless interface
for IFACE in $WIRELESS_INTERFACES; do
    echo "------------------------------"
    echo "Resetting interface: $IFACE"
    
    # Special handling for interfaces ending with "mon" (monitor mode interfaces)
    if [[ "$IFACE" == *"mon" ]]; then
        echo "Detected monitor mode interface: $IFACE"
        BASE_IFACE=$(echo $IFACE | sed 's/mon$//')
        
        echo "Base interface should be: $BASE_IFACE"
        
        # First try airmon-ng if available
        if [ $HAS_AIRCRACK -eq 1 ]; then
            echo "Using airmon-ng to stop monitor mode..."
            airmon-ng stop $IFACE
            sleep 0.5  # Give airmon-ng a moment to complete
        fi
        
        # Even if airmon-ng was used, let's make sure the monitor interface is gone
        if ip link show $IFACE &>/dev/null; then
            echo "Monitor interface still exists, removing manually..."
            # Get the physical device number before deleting the interface
            PHY=$(iw dev $IFACE info 2>/dev/null | grep wiphy | awk '{print $2}')
            if [ -z "$PHY" ]; then
                echo "Could not determine PHY for $IFACE, trying alternative method..."
                PHY=$(ls -l /sys/class/net/$IFACE/phy80211/index 2>/dev/null | awk -F'/' '{print $NF}')
            fi
            
            echo "Found PHY: phy$PHY"
            
            # Delete the monitor interface
            ip link set $IFACE down
            iw dev $IFACE del
        else
            echo "Monitor interface already removed by airmon-ng"
        fi
        
        # Check if base interface exists, if not, create it
        if ! ip link show $BASE_IFACE &>/dev/null; then
            echo "Base interface $BASE_IFACE not found, creating it..."
            
            # If we have the PHY number, use it to create the base interface
            if [ ! -z "$PHY" ]; then
                echo "Creating $BASE_IFACE on phy$PHY..."
                iw phy phy$PHY interface add $BASE_IFACE type managed
                
                if [ $? -eq 0 ]; then
                    echo "Successfully created $BASE_IFACE"
                else
                    echo "Failed to create $BASE_IFACE"
                fi
            else
                echo "Cannot create base interface - PHY number is unknown"
            fi
        fi
        
        # Make sure base interface is up if it exists
        if ip link show $BASE_IFACE &>/dev/null; then
            echo "Bringing up base interface $BASE_IFACE..."
            ip link set $BASE_IFACE up
            ip link set $BASE_IFACE promisc off
            
            # Reset interface MAC if needed and if macchanger is available
            if command -v macchanger &> /dev/null; then
                echo "Resetting MAC address for $BASE_IFACE..."
                macchanger -p $BASE_IFACE &>/dev/null
            fi
        else
            echo "WARNING: Base interface $BASE_IFACE does not exist"
        fi
        
        # Skip the rest of this iteration as we've handled the monitor interface
        echo "Monitor interface $IFACE handled"
        continue
    fi
    
    # For regular interfaces, check if interface is in monitor mode
    MODE=$(iwconfig $IFACE 2>/dev/null | grep -o "Mode:[^ ]*" | cut -d ":" -f2)
    
    if [ "$MODE" = "Monitor" ]; then
        echo "Interface is in monitor mode. Taking it out..."
        # Bring interface down
        ip link set $IFACE down
        # Take interface out of monitor mode
        iw dev $IFACE set type managed
        echo "Changed mode from Monitor to Managed"
    fi
    
    # Flush IP address
    echo "Flushing IP address..."
    ip addr flush dev $IFACE
    
    # Reset interface by bringing it down and up again
    echo "Bringing interface down..."
    ip link set $IFACE down
    
    # Minimal delay to ensure interface is fully down
    sleep 0.2
    
    echo "Bringing interface up..."
    ip link set $IFACE up
    
    # Restart networking service (works on most distributions)
    if command -v systemctl &> /dev/null; then
        echo "Restarting NetworkManager..."
        systemctl restart NetworkManager.service &> /dev/null || \
        systemctl restart network-manager.service &> /dev/null || \
        systemctl restart networking.service &> /dev/null
    elif command -v service &> /dev/null; then
        echo "Restarting networking service..."
        service network-manager restart &> /dev/null || \
        service networking restart &> /dev/null
    fi
    
    # Only release DHCP lease without requesting a new one
    if command -v dhclient &> /dev/null; then
        echo "Releasing DHCP lease..."
        dhclient -r $IFACE
    else
        echo "dhclient not found - skipping DHCP release"
    fi
    
    echo "Reset complete for $IFACE"
done

# After processing all interfaces, check for any missing base interfaces
echo "------------------------------"
echo "Checking for missing base interfaces..."

# Get the list of all physical devices
PHYS=$(iw list 2>/dev/null | grep -i "wiphy" | awk '{print $2}')

for PHY in $PHYS; do
    # Check if there's an interface for this PHY
    IFACE_FOR_PHY=$(iw dev | grep -A 1 "phy#$PHY" | grep "Interface" | awk '{print $2}')
    
    # If no interface exists for this PHY, create one
    if [ -z "$IFACE_FOR_PHY" ]; then
        echo "No interface found for phy$PHY"
        
        # Try to determine what the interface should be named
        # This is a guess - might need adjustment based on your system
        NEW_IFACE="wlan$PHY"
        
        echo "Creating interface $NEW_IFACE on phy$PHY..."
        iw phy phy$PHY interface add $NEW_IFACE type managed
        
        if [ $? -eq 0 ]; then
            echo "Successfully created $NEW_IFACE"
            ip link set $NEW_IFACE up
        else
            echo "Failed to create interface for phy$PHY"
        fi
    fi
done

echo "------------------------------"
echo "All wireless interfaces have been reset."
echo "Current network status:"

# Get updated list of interfaces after all operations
CURRENT_INTERFACES=$(iw dev | grep Interface | awk '{print $2}')
ip addr | grep -A 5 "$(echo "$CURRENT_INTERFACES" | sed 's/$/\\|/g' | tr -d '\n' | sed 's/\\|$//')"

echo "------------------------------"
echo "Physical devices and their interfaces:"
iw dev

exit 0
