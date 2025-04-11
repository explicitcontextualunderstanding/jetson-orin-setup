#!/bin/bash

set -e

sudo apt update && sudo apt upgrade -y
snap install chromium
sudo apt install python3-pip
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

echo "Running Visual Studio Code installation..."
# Execute the VS Code installation script with sudo
sudo bash "$VSCODE_SCRIPT"

if [ $? -eq 0 ]; then
  echo "Visual Studio Code installation completed successfully."
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

