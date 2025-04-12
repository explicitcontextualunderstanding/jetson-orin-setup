#!/bin/bash

# pin_to_dock.sh: Pin an application to the GNOME dock

set -e

if [ -z "$1" ]; then
  echo "Error: Please specify the .desktop file (e.g., 'code.desktop')."
  exit 1
fi

DESKTOP_FILE="$1"
# Format for gsettings list: strings must be single-quoted
APP_TO_ADD="'$DESKTOP_FILE'"

# Verify the .desktop file exists in standard locations
if [ -f "/usr/share/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="/usr/share/applications/$DESKTOP_FILE"
elif [ -f "/var/lib/snapd/desktop/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="/var/lib/snapd/desktop/applications/$DESKTOP_FILE"
elif [ -f "$HOME/.local/share/applications/$DESKTOP_FILE" ]; then
  DESKTOP_PATH="$HOME/.local/share/applications/$DESKTOP_FILE"
else
  echo "Error: $DESKTOP_FILE not found in standard locations."
  exit 1
fi

echo "Found $DESKTOP_FILE at $DESKTOP_PATH"

# Check if gsettings is available
if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings command not found. Is GNOME installed correctly?"
  exit 1
fi

# Get current favorites list directly as the user
CURRENT_FAVORITES=$(gsettings get org.gnome.shell favorite-apps)

# Check if the app (in its quoted form) is already pinned
if echo "$CURRENT_FAVORITES" | grep -qF "$APP_TO_ADD"; then
  echo "$DESKTOP_FILE is already pinned to the dock."
  exit 0
fi

# Construct the new list
# Check if the current list is empty (handles '[]' and GVariant '@as []')
if [ "$CURRENT_FAVORITES" == "[]" ] || [ "$CURRENT_FAVORITES" == "@as []" ]; then
  NEW_FAVORITES="[$APP_TO_ADD]"
else
  # Append to the existing list
  # Remove the trailing ']'
  TEMP_FAVORITES=${CURRENT_FAVORITES%]}
  # Add the new app (comma, space, quoted app name) and the closing ']'
  NEW_FAVORITES="${TEMP_FAVORITES}, $APP_TO_ADD]"
fi

# Set the new favorites list directly as the user
if gsettings set org.gnome.shell favorite-apps "$NEW_FAVORITES"; then
  echo "Successfully pinned $DESKTOP_FILE to the GNOME dock."
else
  # Provide a more specific error message if possible
  echo "Error: gsettings command failed to pin $DESKTOP_FILE to the dock."
  exit 1
fi

exit 0
