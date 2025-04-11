#!/bin/bash

# setup_jetson.sh: Automate post-flashing setup for NVIDIA Jetson Orin

set -e

# Path to scripts
PIN_SCRIPT="./scripts/pin_to_dock.sh"
TERMINAL_FONT_SCRIPT="./scripts/set_terminal_font.sh"

# Check if the pin script exists
if [ ! -f "$PIN_SCRIPT" ]; then
  echo "Warning: $PIN_SCRIPT not found. Skipping dock pinning."
  PIN_SCRIPT=""
else
  # Check if the pin script is executable
  if [ ! -x "$PIN_SCRIPT" ]; then
    echo "Making $PIN_SCRIPT executable..."
    chmod +x "$PIN_SCRIPT"
  fi
fi

# Check if the terminal font script exists
if [ ! -f "$TERMINAL_FONT_SCRIPT" ]; then
  echo "Warning: $TERMINAL_FONT_SCRIPT not found. Skipping terminal font customization."
  TERMINAL_FONT_SCRIPT=""
else
  # Check if the terminal font script is executable
  if [ ! -x "$TERMINAL_FONT_SCRIPT" ]; then
    echo "Making $TERMINAL_FONT_SCRIPT executable..."
    chmod +x "$TERMINAL_FONT_SCRIPT"
  fi
fi

# Update and upgrade system
sudo apt update && sudo apt upgrade -y

# Pin Terminal to dock
if [ -n "$PIN_SCRIPT" ]; then
  echo "Pinning Terminal to the dock..."
  sudo bash "$PIN_SCRIPT" org.gnome.Terminal.desktop || echo "Warning: Failed to pin Terminal to dock."
fi

if [ -n "$TERMINAL_FONT_SCRIPT" ]; then
  echo "Setting Terminal font size to 16..."
  sudo bash "$TERMINAL_FONT_SCRIPT" || echo "Warning: Failed to set Terminal font size."
fi


# Install Chromium via snap
snap install chromium

# Pin Chromium to dock
if [ -n "$PIN_SCRIPT" ]; then
  echo "Pinning Chromium to the dock..."
  sudo bash "$PIN_SCRIPT" chromium_chromium.desktop || echo "Warning: Failed to pin Chromium to dock."
fi

# Install Python3 pip
sudo apt install python3-pip

# Install jetson-stats
sudo pip3 install -U jetson-stats

# Path to the VS Code installation script
VSCODE_SCRIPT="./scripts/install_vscode.sh"

# Check if the VS Code script exists
if [ ! -f "$VSCODE_SCRIPT" ]; then
  echo "Error: $VSCODE_SCRIPT not found."
  exit 1
fi

# Check if the VS Code script is executable
if [ ! -x "$VSCODE_SCRIPT" ]; then
  echo "Making $VSCODE_SCRIPT executable..."
  chmod +x "$VSCODE_SCRIPT"
fi

# Run VS Code installation
echo "Running Visual Studio Code installation..."
# Execute the VS Code installation script with sudo
sudo bash "$VSCODE_SCRIPT"

if [ $? -eq 0 ]; then
  echo "Visual Studio Code installation completed successfully."
  # Pin VS Code to dock
  if [ -n "$PIN_SCRIPT" ]; then
    echo "Pinning Visual Studio Code to the dock..."
    sudo bash "$PIN_SCRIPT" code.desktop || echo "Warning: Failed to pin VS Code to dock."
  fi
else
  echo "Error: Visual Studio Code installation failed."
  exit 1
fi

# Check if reboot is needed
if [ -f /var/run/reboot-required ]; then
  echo "Setup complete. A reboot is required to finalize changes."
  echo "Reboot now? (y/N)"
  read -r reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
  else
    echo "Please reboot manually later to complete setup."
  fi
else
  # jtop requires login/out or restart
  echo "Setup complete. Please reboot to complete setup"
fi
