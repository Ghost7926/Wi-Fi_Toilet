# Wi-Fi_Toilet

A script to fully reset all wireless adapters on your system.

## Features

- Detects and properly resets all wireless interfaces
- Handles monitor mode interfaces (wlan0mon, etc.)
- Flushes IP addresses
- Releases DHCP leases
- Recreates base interfaces when needed
  
## Installation

```bash
git clone https://github.com/yourusername/Wi-Fi_Toilet.git
cd Wi-Fi_Toilet
chmod +x wifi_toilet.sh
```

## Usage

```bash
sudo ./wifi_toilet.sh
```
