#!/bin/bash

# setup_jetson.sh: Automate post-flashing setup for NVIDIA Jetson Orin with logging

# --- Logging Setup ---
LOG_DIR="$(pwd)" # Log directory (current directory)
LOG_FILE="${LOG_DIR}/setup_jetson_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE" # Create the log file upfront
chmod 644 "$LOG_FILE" # Set permissions (adjust if needed)

# Logging function: log_message LEVEL "message"
# LEVEL can be INFO, WARN, ERROR
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    # Log to file and print to stdout
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to log command output (optional, use if you want full command logs)
log_command_output() {
    local cmd_string="$@"
    log_message "INFO" "Executing command: $cmd_string"
    # Execute command, redirecting stdout and stderr to the log file
    # Use sudo if the command needs it
    if [[ "$cmd_string" == sudo* ]]; then
        eval "$cmd_string" >> "$LOG_FILE" 2>&1
    else
        eval "$cmd_string" >> "$LOG_FILE" 2>&1
    fi

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "Command failed with exit code $exit_code: $cmd_string"
    else
         log_message "INFO" "Command finished successfully: $cmd_string"
    fi
    return $exit_code
}


# --- Script Start ---
log_message "INFO" "Starting Jetson setup script. Log file: $LOG_FILE"

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Path to scripts relative to this setup script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PIN_SCRIPT="${SCRIPT_DIR}/scripts/pin_to_dock.sh"
TERMINAL_FONT_SCRIPT="${SCRIPT_DIR}/scripts/set_terminal_font.sh"
VSCODE_SCRIPT="${SCRIPT_DIR}/scripts/install_vscode.sh"

# --- Script Checks ---
log_message "INFO" "Checking for necessary helper scripts..."

# Check if the pin script exists
if [ ! -f "$PIN_SCRIPT" ]; then
  log_message "WARN" "$PIN_SCRIPT not found. Skipping all dock pinning actions."
  PIN_SCRIPT="" # Clear the variable so checks later fail safely
else
  log_message "INFO" "$PIN_SCRIPT found."
  # Check if the pin script is executable
  if [ ! -x "$PIN_SCRIPT" ]; then
    log_message "INFO" "Making $PIN_SCRIPT executable..."
    chmod +x "$PIN_SCRIPT"
  fi
fi

# Check if the terminal font script exists
if [ ! -f "$TERMINAL_FONT_SCRIPT" ]; then
  log_message "WARN" "$TERMINAL_FONT_SCRIPT not found. Skipping terminal font customization."
  TERMINAL_FONT_SCRIPT=""
else
   log_message "INFO" "$TERMINAL_FONT_SCRIPT found."
  # Check if the terminal font script is executable
  if [ ! -x "$TERMINAL_FONT_SCRIPT" ]; then
    log_message "INFO" "Making $TERMINAL_FONT_SCRIPT executable..."
    chmod +x "$TERMINAL_FONT_SCRIPT"
  fi
fi

# Check if the VS Code script exists
if [ ! -f "$VSCODE_SCRIPT" ]; then
  log_message "ERROR" "$VSCODE_SCRIPT not found. Cannot install VS Code."
  log_message "ERROR" "Setup script cannot continue without VS Code script. Exiting."
  exit 1 # Exit because VS Code install is treated as critical later
else
  log_message "INFO" "$VSCODE_SCRIPT found."
  # Check if the VS Code script is executable
  if [ ! -x "$VSCODE_SCRIPT" ]; then
    log_message "INFO" "Making $VSCODE_SCRIPT executable..."
    chmod +x "$VSCODE_SCRIPT"
  fi
fi

# --- GNOME Terminal Setup ---
# Pin Terminal to dock
if [ -n "$PIN_SCRIPT" ]; then
  log_message "INFO" "Pinning Terminal to the dock..."
  bash "$PIN_SCRIPT" org.gnome.Terminal.desktop || log_message "WARN" "Failed to pin Terminal to dock. Script: $PIN_SCRIPT"
else
  log_message "INFO" "Skipping Terminal pinning (script not found)."
fi

# Set Terminal font size
if [ -n "$TERMINAL_FONT_SCRIPT" ]; then
  log_message "INFO" "Setting Terminal font size to 16..."
  bash "$TERMINAL_FONT_SCRIPT" || log_message "WARN" "Failed to set Terminal font size. Script: $TERMINAL_FONT_SCRIPT"
else
  log_message "INFO" "Skipping Terminal font setting (script not found)."
fi

# --- System Update ---
log_message "INFO" "Starting system update..."
# Optional: Use log_command_output if you want detailed apt logs in the file
# log_command_output sudo apt update
sudo apt update 
log_message "INFO" "System update completed."

# --- Chromium Installation ---
log_message "INFO" "Installing Chromium via snap..."
# Optional: Use log_command_output for detailed snap logs
# log_command_output snap install chromium
# Note: I've had issues with installation using
# sudo snap install chromium
# apt install still uses the snap installer, but seems to have less issues
sudo apt install chromium-browser
log_message "INFO" "Chromium installation completed."

# Pin Chromium to dock
if [ -n "$PIN_SCRIPT" ]; then
  log_message "INFO" "Pinning Chromium to the dock..."
  bash "$PIN_SCRIPT" chromium_chromium.desktop || log_message "WARN" "Failed to pin Chromium to dock. Script: $PIN_SCRIPT"
else
  log_message "INFO" "Skipping Chromium pinning (script not found)."
fi

# --- Python pip Installation ---
log_message "INFO" "Installing Python3 pip..."
# Optional: Use log_command_output for detailed apt logs
# log_command_output sudo apt install python3-pip -y
sudo apt install python3-pip -y # Added -y to avoid prompt
log_message "INFO" "Python3 pip installation completed."

# --- jetson-stats Installation ---
log_message "INFO" "Installing/Updating jetson-stats..."
# Optional: Use log_command_output for detailed pip logs
# log_command_output sudo pip3 install -U jetson-stats
sudo pip3 install -U jetson-stats
log_message "INFO" "jetson-stats installation/update completed."

# --- System Update ---
log_message "INFO" "Starting system update and upgrade..."
# Optional: Use log_command_output if you want detailed apt logs in the file
# log_command_output sudo apt upgrade -y
sudo apt upgrade -y
log_message "INFO" "System upgrade completed."


# --- VS Code Installation ---
log_message "INFO" "Running Visual Studio Code installation script: $VSCODE_SCRIPT..."
# Optional: Use log_command_output if you want detailed VSCode script logs
# log_command_output sudo bash "$VSCODE_SCRIPT"
sudo bash "$VSCODE_SCRIPT"

if [ $? -eq 0 ]; then
  log_message "INFO" "Visual Studio Code installation completed successfully."
  # Pin VS Code to dock
  if [ -n "$PIN_SCRIPT" ]; then
    log_message "INFO" "Pinning Visual Studio Code to the dock..."
    bash "$PIN_SCRIPT" code.desktop || log_message "WARN" "Failed to pin VS Code to dock. Script: $PIN_SCRIPT"
  else
    log_message "INFO" "Skipping VS Code pinning (script not found)."
  fi
else
  # Note: set -e might cause the script to exit before this point if sudo bash fails
  # Keeping this block in case set -e is removed or the script structure changes
  log_message "ERROR" "Visual Studio Code installation script failed."
  log_message "ERROR" "Setup script finished with errors."
  exit 1
fi

# --- Final Steps ---
# Check if reboot is needed
if [ -f /var/run/reboot-required ]; then
  log_message "INFO" "System indicates a reboot is required."
  echo # Add a newline for better readability of the prompt
  log_message "INFO" "Setup complete. A reboot is required to finalize changes."
  echo "Reboot now? (y/N)"
  read -r reboot_choice
  log_message "INFO" "User input for reboot: $reboot_choice"
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log_message "INFO" "User chose to reboot. Rebooting in 5 seconds..."
    echo "Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
  else
    log_message "INFO" "User chose not to reboot now. Please reboot manually later."
    echo "Please reboot manually later to complete setup."
  fi
else
  # jtop often requires login/out or restart even if /var/run/reboot-required isn't present
  log_message "INFO" "Setup complete. No mandatory reboot flag found, but a reboot is recommended (e.g., for jtop)."
  echo "Setup complete. Please reboot or log out/in to ensure all changes take effect (especially for tools like jtop)."
fi

log_message "INFO" "Jetson setup script finished."
exit 0
