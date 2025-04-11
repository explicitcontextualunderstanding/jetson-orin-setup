#!/bin/bash

# set_terminal_font.sh: Set GNOME Terminal default profile font size to 16

set -e

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo to access user environment."
  exit 1
fi

# Get the original user
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
if [ "$ORIGINAL_USER" = "root" ]; then
  echo "Error: Cannot set terminal font for root user. Please run as a regular user with sudo."
  exit 1
fi

# Check if gsettings is available
if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings not found. Please install gnome-settings-daemon."
  exit 1
fi

# Get the list of profiles
PROFILE_LIST=$(sudo -u "$ORIGINAL_USER" gsettings get org.gnome.terminal.legacy.profiles: list)

# If no profiles exist, create a new one
if [ "$PROFILE_LIST" = "[]" ]; then
  echo "No profiles found. Creating a new default profile..."
  NEW_PROFILE=$(uuidgen)
  sudo -u "$ORIGINAL_USER" gsettings set org.gnome.terminal.legacy.profiles: list "['$NEW_PROFILE']"
  sudo -u "$ORIGINAL_USER" dconf write /org/gnome/terminal/legacy/profiles:/:$NEW_PROFILE/visible-name "'Default'"
else
  # Get the first profile (usually the default)
  NEW_PROFILE=$(echo "$PROFILE_LIST" | sed "s/[][]//g" | tr -d "'" | awk '{print $1}')
fi

# Set the default profile
sudo -u "$ORIGINAL_USER" gsettings set org.gnome.terminal.legacy default "$NEW_PROFILE"

# Set font settings for the profile
PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$NEW_PROFILE/"
sudo -u "$ORIGINAL_USER" gsettings set org.gnome.terminal.legacy.profiles: "$PROFILE_PATH" use-system-font false
sudo -u "$ORIGINAL_USER" gsettings set org.gnome.terminal.legacy.profiles: "$PROFILE_PATH" font "'Monospace 16'"

echo "GNOME Terminal font size set to 16 for profile $NEW_PROFILE."

exit 0
