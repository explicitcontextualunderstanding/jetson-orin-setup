#!/bin/bash

# set_terminal_font.sh: Set GNOME Terminal default profile font size to 16
# Run this script AS the user whose terminal you want to configure. DO NOT use sudo.
# Sets the font size for new GNOME Terminal windows.

set -e # Exit immediately if a command exits with a non-zero status.
#set -u #Uncomment this to treat unset variables as an error

# --- Configuration ---
TARGET_FONT="Monospace 16"
# --- End Configuration ---

# Check if essential commands exist
if ! command -v gsettings &> /dev/null || ! command -v dconf &> /dev/null; then
    echo "Error: Required commands 'gsettings' or 'dconf' not found." >&2
    exit 1
fi

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
  echo "Error: This script must be run directly by the user, NOT with sudo." >&2
  exit 1
fi

# Check for Snap version of GNOME Terminal (potential complication)
if snap list gnome-terminal &> /dev/null; then
    echo "Warning: A Snap version of GNOME Terminal is installed. This script might not work correctly." >&2
    echo "Consider using the APT version: sudo snap remove gnome-terminal && sudo apt update && sudo apt install gnome-terminal" >&2
fi

# Schema for ProfilesList (needed for default UUID)
SCHEMA_PROFILES="org.gnome.Terminal.ProfilesList"

# Verify ProfilesList schema exists
if ! gsettings list-schemas | grep -q "$SCHEMA_PROFILES"; then
  echo "Error: Schema '$SCHEMA_PROFILES' not found. Is GNOME Terminal (APT version) properly installed?" >&2
  exit 1
fi

# Get the default profile UUID
DEFAULT_PROFILE_UUID=$(gsettings get "$SCHEMA_PROFILES" default)
DEFAULT_PROFILE_UUID=$(echo "$DEFAULT_PROFILE_UUID" | tr -d "'")

# Handle case where default isn't set
if [ -z "$DEFAULT_PROFILE_UUID" ]; then
    PROFILE_LIST_RAW=$(gsettings get "$SCHEMA_PROFILES" list)
    FIRST_PROFILE_UUID=$(echo "$PROFILE_LIST_RAW" | sed -e "s/^[^']*'//" -e "s/'.*//" | head -n 1)
    if [ -n "$FIRST_PROFILE_UUID" ]; then
        DEFAULT_PROFILE_UUID="$FIRST_PROFILE_UUID"
        gsettings set "$SCHEMA_PROFILES" default "$DEFAULT_PROFILE_UUID"
    else
        echo "Error: No default profile set and no profiles found. Please configure a default profile in GNOME Terminal preferences." >&2
        exit 1
    fi
fi

# Define the dconf path based on the schema and observed structure
PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:${DEFAULT_PROFILE_UUID}/"

# Check if the dconf path exists
if ! dconf list "$PROFILE_PATH" &> /dev/null; then
    echo "Warning: Profile path '$PROFILE_PATH' not found. Proceeding to write, but the profile may not have been modified before." >&2
fi

# Apply settings
dconf write "${PROFILE_PATH}use-system-font" "false"
dconf write "${PROFILE_PATH}font" "'$TARGET_FONT'"

# Verify settings after write
FINAL_FONT=$(dconf read "${PROFILE_PATH}font")
FINAL_USE_SYS=$(dconf read "${PROFILE_PATH}use-system-font")

if [ "$FINAL_FONT" != "'$TARGET_FONT'" ] || [ "$FINAL_USE_SYS" != "false" ]; then
    echo "Error: Failed to set GNOME Terminal font size.  Verification failed." >&2
    exit 1
fi

echo "GNOME Terminal font size set to '$TARGET_FONT'. Open a NEW Terminal window to see the changes."
exit 0

