#!/bin/bash

# pin_to_dock.sh: Pin an application to the GNOME dock on Jetson (Ubuntu 20.04+)

set -e

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo to access user environment."
  exit 1
fi

# Get the original user
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
if [ "$ORIGINAL_USER" = "root" ]; then
  echo "Error: Cannot pin app for root user. Please run as a regular user with sudo."
  exit 1
fi

# Check if an app argument was provided
if [ -z "$1" ]; then
  echo "Error: Please specify the .desktop file (e.g., 'code.desktop')."
  exit 1
fi

DESKTOP_FILE="$1"

# Verify the .desktop file exists
if [ -f "/usr/share/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="/usr/share/applications/$DESKTOP_FILE"
elif [ -f "/var/lib/snapd/desktop/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="/var/lib/snapd/desktop/applications/$DESKTOP_FILE"
elif [ -f "/home/$ORIGINAL_USER/.local/share/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="/home/$ORIGINAL_USER/.local/share/applications/$DESKTOP_FILE"
else
  echo "Error: $DESKTOP_FILE not found in standard locations."
  exit 1
fi

echo "Found $DESKTOP_FILE at $DESKTOP_PATH"

# Check if gsettings is available
if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings not found. Please install gnome-settings-daemon."
  exit 1
fi

# Get current favorites
CURRENT_FAVORITES=$(sudo -u "$ORIGINAL_USER" gsettings get org.gnome.shell favorite-apps)

# Check if the app is already pinned
if echo "$CURRENT_FAVORITES" | grep -q "$DESKTOP_FILE"; then
  echo "$DESKTOP_FILE is already pinned to the dock."
  exit 0
fi

# Add the app to favorites
NEW_FAVORITES=$(echo "$CURRENT_FAVORITES" | sed "s/]$/, '$DESKTOP_FILE']/")
if sudo -u "$ORIGINAL_USER" gsettings set org.gnome.shell favorite-apps "$NEW_FAVORITES"; then
  echo "Successfully pinned $DESKTOP_FILE to the GNOME dock."
else
  echo "Error: Failed to pin $DESKTOP_FILE to the dock."
  exit 1
fi

exit 0
