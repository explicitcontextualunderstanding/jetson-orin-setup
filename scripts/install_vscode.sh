#!/bin/bash

# Script to download and install the latest Visual Studio Code for NVIDIA Jetson Orin Nano (ARM64)
# Saves the .deb file with the same name as on the server

# Exit on any error
set -e

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

# Determine the original user
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  ORIGINAL_USER="$SUDO_USER"
else
  # Fallback: use the first non-root user with a home directory
  ORIGINAL_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -n 1)
  if [ -z "$ORIGINAL_USER" ]; then
    ORIGINAL_USER="nobody"
  fi
fi

echo "Original user detected as: $ORIGINAL_USER"

echo "Updating package lists..."
apt-get update

echo "Installing required dependencies..."
apt-get install -y wget apt-transport-https

# Directory to store the downloaded file
DOWNLOAD_DIR="/tmp"
DOWNLOAD_URL="https://update.code.visualstudio.com/latest/linux-deb-arm64/stable"

echo "Fetching the latest Visual Studio Code ARM64 .deb package..."

# Get the filename from the server's response headers
FILENAME=$(wget --spider "$DOWNLOAD_URL" 2>&1 | grep -oP 'filename="\K[^"]+' || true)

if [ -z "$FILENAME" ]; then
  echo "Warning: Could not determine server filename. Using fallback name 'vscode_latest_arm64.deb'."
  FILENAME="vscode_latest_arm64.deb"
fi

# Full path for the downloaded file
DEB_FILE="$DOWNLOAD_DIR/$FILENAME"

# Download the file with the original filename
wget -O "$DEB_FILE" "$DOWNLOAD_URL"

if [ ! -s "$DEB_FILE" ]; then
  echo "Error: Failed to download the .deb package."
  rm -f "$DEB_FILE"
  exit 1
fi

echo "Downloaded file saved as: $DEB_FILE"

echo "Installing Visual Studio Code..."
# Install the downloaded .deb file
dpkg -i "$DEB_FILE" || {
  echo "Fixing missing dependencies..."
  apt-get install -f -y
}

echo "Cleaning up..."
# Remove the downloaded .deb file
rm -f "$DEB_FILE"

echo "Verifying installation..."
# Verify as the original user if possible, otherwise check directly
if [ "$ORIGINAL_USER" != "nobody" ] && [ "$ORIGINAL_USER" != "root" ]; then
  if sudo -u "$ORIGINAL_USER" bash -c 'command -v code >/dev/null 2>&1'; then
    echo "VS Code version:"
    sudo -u "$ORIGINAL_USER" code --version
    echo "Visual Studio Code installed successfully!"
  else
    echo "Error: Visual Studio Code installation failed."
    exit 1
  fi
else
  # Fallback: verify directly (e.g., running as root)
  if command -v code >/dev/null 2>&1; then
    echo "VS Code version:"
    code --version
    echo "Visual Studio Code installed successfully!"
  else
    echo "Error: Visual Studio Code installation failed."
    exit 1
  fi
fi

exit 0
