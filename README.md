# jetson-orin-setup
After flashing, installs the minimum development environment

# Jetson Orin Nano Setup

A script to automate post-flashing setup for NVIDIA Jetson Orin Nano on JetPack 5.x or later. I use these scripts frequently for setting up a minimal development environment

## Features
- Verifies JetPack version (> 4) (Latest version of VSCode requirement)
- Updates system packages
- Installs Chromium (via snap), python3-pip, jetson-stats, and Visual Studio Code
- Checks for reboot requirements

## Requirements
- NVIDIA Jetson Xavier, Jetson Orin (AGX Orin, Orin Nano Super, Orin Nano, Orin NX)
- JetPack 5.x or later (Ubuntu 20.04+)
- Internet connection
- `install_vscode.sh` in the scripts directory

## Usage
```bash
git clone https://github.com/yourusername/jetson-orin-setup.git
cd jetson-orin-nano-setup
chmod +x setup_jetson.sh
./setup_jetson.sh
