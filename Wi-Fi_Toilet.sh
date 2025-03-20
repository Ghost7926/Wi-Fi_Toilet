#!/bin/bash

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
        
        # Simply note that the monitor interface has been removed
        echo "Monitor interface $IFACE has been removed"
        
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
    
    # Only release DHCP lease without requesting a new one
    if command -v dhclient &> /dev/null; then
        echo "Releasing DHCP lease..."
        dhclient -r $IFACE
    else
        echo "dhclient not found - skipping DHCP release"
    fi
    
    echo "Reset complete for $IFACE"
done

echo "------------------------------"
echo "All wireless interfaces have been reset."
echo "Current network status:"

# Get updated list of interfaces after all operations
CURRENT_INTERFACES=$(iw dev | grep Interface | awk '{print $2}')
ip addr | grep -A 5 "$(echo "$CURRENT_INTERFACES" | sed 's/$/\\|/g' | tr -d '\n' | sed 's/\\|$//')"


exit 0
