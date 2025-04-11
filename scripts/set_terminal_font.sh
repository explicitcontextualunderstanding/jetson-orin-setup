#!/bin/bash

# set_terminal_font_user.sh: Set GNOME Terminal default profile font size to 16
# Run this script AS the user whose terminal you want to configure. DO NOT use sudo.

set -e # Exit immediately if a command exits with a non-zero status.

# Check if essential commands exist
if ! command -v gsettings &> /dev/null || ! command -v dconf &> /dev/null || ! command -v uuidgen &> /dev/null; then
    echo "Error: Required commands (gsettings, dconf, uuidgen) not found."
    echo "Please ensure 'dconf-cli', 'uuid-runtime', and GNOME Terminal are installed."
    echo "Example: sudo apt update && sudo apt install -y gnome-terminal dconf-cli uuid-runtime"
    exit 1
fi

# Check if running with sudo - this script should NOT be run with sudo
if [ "$EUID" -eq 0 ]; then
  echo "Error: This script should be run directly by the user, not with sudo."
  exit 1
fi

# --- Configuration ---
TARGET_FONT="Monospace 16"
TARGET_FONT_NAME=$(echo "$TARGET_FONT" | awk '{print $1}')
TARGET_FONT_SIZE=$(echo "$TARGET_FONT" | awk '{print $2}')
# --- End Configuration ---


# Check for required schema
SCHEMA_TERMINAL="org.gnome.Terminal.Legacy.Settings"
SCHEMA_PROFILES="org.gnome.Terminal.ProfilesList"

if ! gsettings list-schemas | grep -q "$SCHEMA_PROFILES"; then
  echo "Error: Schema '$SCHEMA_PROFILES' not found."
  echo "Cannot detect GNOME Terminal profiles automatically."
  echo "Is GNOME Terminal properly installed?"
  exit 1
fi

echo "Checking GNOME Terminal profiles..."

# Get the default profile UUID
DEFAULT_PROFILE_UUID=$(gsettings get "$SCHEMA_PROFILES" default)
DEFAULT_PROFILE_UUID=$(echo "$DEFAULT_PROFILE_UUID" | tr -d "'") # Remove single quotes

# Get the list of profile UUIDs
PROFILE_LIST_RAW=$(gsettings get "$SCHEMA_PROFILES" list)
PROFILE_LIST=$(echo "$PROFILE_LIST_RAW" | sed "s/[][]//g" | tr -d ",") # Clean up list format

# Determine the profile UUID to use
PROFILE_UUID=""

if [ -n "$DEFAULT_PROFILE_UUID" ] && echo "$PROFILE_LIST" | grep -qw "$DEFAULT_PROFILE_UUID"; then
    echo "Found default profile: $DEFAULT_PROFILE_UUID"
    PROFILE_UUID="$DEFAULT_PROFILE_UUID"
else
    echo "No valid default profile set or found in list."
    # If list is empty, create a new profile
    if [ "$PROFILE_LIST_RAW" = "@as []" ] || [ "$PROFILE_LIST_RAW" = "[]" ]; then
        echo "No profiles found. Creating a new default profile..."
        PROFILE_UUID=$(uuidgen)
        gsettings set "$SCHEMA_PROFILES" list "['$PROFILE_UUID']"
        gsettings set "$SCHEMA_PROFILES" default "$PROFILE_UUID"
        # Set a visible name for the new profile using dconf
        PROFILE_PATH="/org/gnome/Terminal/Legacy/profiles:/:$PROFILE_UUID/"
        dconf write "${PROFILE_PATH}visible-name" "'Default'"
        echo "Created and set new default profile: $PROFILE_UUID"
    else
        # Get the first profile from the list as a fallback
        PROFILE_UUID=$(echo "$PROFILE_LIST" | awk '{print $1}' | tr -d "'")
        if [ -z "$PROFILE_UUID" ]; then
            echo "Error: Could not determine a profile UUID to use."
            exit 1
        fi
        echo "Warning: Using first profile found as default: $PROFILE_UUID"
        gsettings set "$SCHEMA_PROFILES" default "$PROFILE_UUID"
    fi
fi

# Define the dconf path for the selected profile
# Note: The path structure changed in newer GNOME versions
# Trying the common path structure for GNOME Terminal profiles
PROFILE_PATH_LEGACY="/org/gnome/Terminal/Legacy/profiles:/:$PROFILE_UUID/"

echo "Setting font for profile: $PROFILE_UUID"

# Check if profile path exists before writing
if dconf list "$PROFILE_PATH_LEGACY" &> /dev/null; then
    # Set font settings using dconf
    dconf write "${PROFILE_PATH_LEGACY}use-system-font" "false"
    dconf write "${PROFILE_PATH_LEGACY}font" "'$TARGET_FONT'"
    echo "Font set to '$TARGET_FONT' for profile $PROFILE_UUID."
    echo "Changes will apply to new Terminal windows."
else
     echo "Error: dconf path '$PROFILE_PATH_LEGACY' not found for profile UUID '$PROFILE_UUID'."
     echo "Profile configuration structure might differ."
     # Attempt alternative path structure (less common now but possible)
     ALT_PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_UUID/"
     if dconf list "$ALT_PROFILE_PATH" &> /dev/null; then
         echo "Attempting alternative path: $ALT_PROFILE_PATH"
         dconf write "${ALT_PROFILE_PATH}use-system-font" "false"
         dconf write "${ALT_PROFILE_PATH}font" "'$TARGET_FONT'"
         echo "Font set to '$TARGET_FONT' for profile $PROFILE_UUID using alternative path."
         echo "Changes will apply to new Terminal windows."
     else
        echo "Error: Could not find a valid dconf path for the profile."
        echo "Please set the font manually via Terminal -> Preferences -> Profile -> Text."
        exit 1
     fi
fi

exit 0
