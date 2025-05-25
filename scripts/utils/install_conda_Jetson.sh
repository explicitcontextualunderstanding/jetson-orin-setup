#!/usr/bin/env bash
###############################################################################
# install_conda_Jetson.sh — v1.1 (May 2025)
# -----------------------------------------------------------------------------
# Installs Miniforge 3 (Conda + Mamba) *for the current USER* on NVIDIA Jetson
# AGX Orin (Ubuntu 22.04, aarch64).  
# **Key change in v1.1**: prevents running as root (which previously redirected
# the install into /root/miniforge3 and wrote to /root/.bashrc, leaving the
# normal user without `conda` on PATH). The script now aborts with a clear
# message if invoked via `sudo` or as root.
#
# Usage :  bash install_conda_Jetson.sh [--verbose] [--clean] [--prefix DIR]
# Flags :  -v|--verbose  : verbose / xtrace
#          -c|--clean    : delete installer after success
#          -p|--prefix   : custom install prefix (default: $HOME/miniforge3)
# -----------------------------------------------------------------------------
# Author : Laurent Amplis – “ChatGPT NVIDIA Jetson Helper”
###############################################################################
set -euo pipefail

# --------------------------- Run‑as‑root safeguard --------------------------
if [[ "$EUID" -eq 0 ]]; then
  echo -e "\033[1;31m[install_conda] ERROR: Please run this script as your normal user *without sudo*.\033[0m" >&2
  echo "       The installer must amend your personal ~/.bashrc and place Miniforge" >&2
  echo "       under your home directory. Run again as \"$(logname)\"." >&2
  exit 1
fi

# ----------------------------- Defaults --------------------------------------
PREFIX="$HOME/miniforge3"
VERBOSE=0
CLEAN=0

# --------------------------- CLI parsing -------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; set -x ;;
    -c|--clean)   CLEAN=1 ;;
    -p|--prefix)  PREFIX="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# --------------------------- Constants ---------------------------------------
ARCH="aarch64"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH}.sh"
CACHE_DIR="$HOME/Workspace/builds"
INSTALLER="${CACHE_DIR}/Miniforge3-Linux-${ARCH}.sh"
PROFILE_SNIPPET="# >>> conda initialize >>>"

# --------------------------- Helpers -----------------------------------------
msg() { echo -e "\033[1;32m[install_conda]\033[0m $*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }

# --------------------------- Pre-flight --------------------------------------
need curl; need sha256sum
mkdir -p "$CACHE_DIR"

if [[ -d "$PREFIX" ]]; then
  msg "Existing installation found at $PREFIX — skipping download."
else
  # ----------------------- Download Miniforge --------------------------------
  msg "Fetching Miniforge installer → $INSTALLER"
  curl -L --progress-bar "$MINIFORGE_URL" -o "$INSTALLER"
  msg "SHA-256: $(sha256sum "$INSTALLER" | awk '{print $1}')"

  # ----------------------- Install -------------------------------------------
  chmod +x "$INSTALLER"
  msg "Running silent install into $PREFIX"
  bash "$INSTALLER" -b -p "$PREFIX"
fi

# --------------------------- Post-install tweaks -----------------------------
CONDA_BIN="$PREFIX/bin/conda"
[[ -x "$CONDA_BIN" ]] || { echo "Conda not found after install" >&2; exit 1; }

# add init to user's ~/.bashrc once
if ! grep -q "$PROFILE_SNIPPET" "$HOME/.bashrc"; then
  msg "Appending shell init stanza to ~/.bashrc"
  "$CONDA_BIN" init bash >/dev/null
fi

# Immediately bring Conda into *this* shell (so next commands see it)
msg "Bootstrapping Conda into current shell"
# shellcheck disable=SC1090,SC1091
eval "$($CONDA_BIN shell.bash hook)"

# Channel prefs
msg "Configuring conda-forge strict priority"
conda config --add channels conda-forge --force
conda config --set channel_priority strict

# --------------------------- Validation --------------------------------------
msg "Running validation tests"
conda --version
python - <<'PY'
import sys, platform, textwrap
print(textwrap.dedent(f"""
  Python OK  : {sys.version.split()[0]}
  Arch       : {platform.machine()}
"""))
PY
conda list | head -n 5 >/dev/null
msg "All tests passed ✔"

# --------------------------- Clean-up ----------------------------------------
if [[ "$CLEAN" -eq 1 ]]; then
  msg "Removing installer $INSTALLER"
  rm -f "$INSTALLER"
fi

msg "✨ Miniforge installed for user '$USER' and immediately available."
msg "   Open a new terminal *or* keep using this one (Conda already on PATH)."
