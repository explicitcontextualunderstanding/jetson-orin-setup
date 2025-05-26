#!/bin/bash

# ============================================================================
# build_pyqt5_arm64.sh
#
# Cross-compile PyQt5 5.10.1 for ARM64 and generate a binary wheel.
# This script is based on a working x86_64 host build with modifications for
# native Jetson Orin / ARM64 targets.
#
# Expected layout:
# - Sources:  $HOME/workspace/sources/pyqt5/PyQt5/tarball/{PyQt5_gpl-5.10.1.tar.gz, sip-4.19.8.tar.gz}
# - Builds:   $HOME/workspace/builds/pyqt5_arm64_build
# - Output:   $HOME/wheels/
#
# Supports:
# --clean   : remove previous builds
# --verbose : enable command tracing
#
# ============================================================================

# --- System preparation (on Jetson/ARM64) ---
# sudo apt update
# sudo apt install -y build-essential qtbase5-dev qtchooser libgl1-mesa-dev python3-dev python3-pip

# (Additional dependencies may be required for packaging and SIP)

# === Preload sudo password once ===
sudo -v

# === Cleanup and environment reset if --clean ===

# Setup vars for cleanup context even before definition
export PYQT_VERSION="5.10.1"
export SIP_VERSION="4.19.8"
export SRC_DIR="$HOME/workspace/sources/pyqt5"
export BUILD_DIR="$HOME/workspace/builds/pyqt5_arm64_build"
export WHEEL_DIR="$HOME/wheels"
export STAGING_DIR="$BUILD_DIR/wheel_staging"

if [[ "$*" == *--clean* ]]; then
  echo "[INFO] Performing full cleanup..."

  # Deactivate conda
  if [[ ! -z "$CONDA_DEFAULT_ENV" ]]; then
    echo "[INFO] Deactivating conda env: $CONDA_DEFAULT_ENV"
    conda deactivate || true
  fi

  # Remove env if it exists
  if conda info --envs | grep -q "dfl-py310"; then
    echo "[INFO] Removing conda env dfl-py310"
    conda env remove -n dfl-py310 -y || true
  fi

  # Uninstall any previous system-level PyQt5 install
  pip uninstall -y pyqt5 || true

  # Clean folders
  rm -rf "$BUILD_DIR" "$WHEEL_DIR/pyqt5-5.10.1-*.whl" "$SRC_DIR/pyqt5"
  rm -rf "$CONDA_PREFIX/lib/python3.10/site-packages/PyQt5" || true
  mkdir -p "$BUILD_DIR" "$WHEEL_DIR"
fi

# === Activate conda environment and dependencies ===

# Load conda environment manually if needed
if ! command -v conda &> /dev/null; then
  echo "[ERROR] Conda is not available. Please install Miniforge or Miniconda."
  exit 1
fi

# Ensure proper conda env is active
if [[ -z "$CONDA_DEFAULT_ENV" || "$CONDA_DEFAULT_ENV" != "dfl-py310" ]]; then
  echo "[INFO] Activating conda environment dfl-py310..."
  eval "$(conda shell.bash hook)" && conda activate dfl-py310 || { echo "[ERROR] Failed to activate dfl-py310."; exit 1; }
fi

# === Define directory layout and version variables ===
export PYQT_VERSION="5.10.1"
export SIP_VERSION="4.19.8"
export TARBALL_DIR="$HOME/workspace/sources/pyqt5/tarball"
export SRC_DIR="$HOME/workspace/sources/pyqt5"
export BUILD_DIR="$HOME/workspace/builds/pyqt5_arm64_build"
export WHEEL_DIR="$HOME/wheels"
export STAGING_DIR="$BUILD_DIR/wheel_staging"

mkdir -p "$BUILD_DIR" "$WHEEL_DIR" "$STAGING_DIR"
cd "$BUILD_DIR"

# === Clone PyQt5 repo and extract SIP ===
cd "$SRC_DIR"
if [ ! -d "$SRC_DIR/pyqt5" ]; then
  echo "[INFO] Cloning baoboa/pyqt5 GitHub repository (tag 5.10.1)..."
  git clone --branch 5.10.1 https://github.com/baoboa/pyqt5.git
fi

# Use SIP tarball from the GitHub-cloned repo's tarball folder
if [ ! -d "$BUILD_DIR/sip-${SIP_VERSION}" ]; then
  echo "[INFO] Extracting SIP from cloned GitHub repo tarball folder..."
  tar -xf "$SRC_DIR/pyqt5/tarball/sip-${SIP_VERSION}.tar.gz" -C "$BUILD_DIR"
fi

cd "$BUILD_DIR/sip-${SIP_VERSION}"
echo "[INFO] Configuring and building SIP..."
python3 configure.py
make -j$(nproc)
sudo make install
cd "$BUILD_DIR"

# === PyQt5 Configuration and Compilation ===

# === Prepare PyQt5 source ===
if [ ! -d "$BUILD_DIR/PyQt5_gpl-${PYQT_VERSION}" ]; then
  echo "[INFO] Copying PyQt5 sources from GitHub repo..."
  cp -r "$SRC_DIR/pyqt5" "$BUILD_DIR/PyQt5_gpl-${PYQT_VERSION}"
fi
echo "[INFO] Entering PyQt5 source directory..."
cd "$BUILD_DIR/PyQt5_gpl-${PYQT_VERSION}"
# Enter extracted PyQt5 sources

# Configure for ARM64 with only available modules
echo "[INFO] Configuring PyQt5 for ARM64..."
python3 configure.py \
  --confirm-license \
  --sip "$(which sip)" \
  --qmake "$(which qmake)" \
  --disable QAxContainer \
  --disable Enginio \
  --disable QtBluetooth \
  --disable QtDesigner \
  --disable QtHelp \
  --disable QtLocation \
  --disable QtMacExtras \
  --disable QtMultimedia \
  --disable QtMultimediaWidgets \
  --disable QtNfc \
  --disable QtPositioning \
  --disable QtQml \
  --disable QtQuick \
  --disable QtQuickWidgets \
  --disable QtSensors \
  --disable QtSerialPort \
  --disable QtSvg \
  --disable QtTest \
  --disable QtWebChannel \
  --disable QtWebEngine \
  --disable QtWebEngineCore \
  --disable QtWebEngineWidgets \
  --disable QtWebKit \
  --disable QtWebKitWidgets \
  --disable QtWebSockets \
  --disable QtWinExtras \
  --disable QtX11Extras \
  --disable QtXmlPatterns \
  --disable QtNetworkAuth \
  --verbose

# Compile
make -j$(nproc)

# Install into current conda environment
sudo make install
# === Package ARM64 Wheel ===

STAGING_DIR="$BUILD_DIR/wheel_staging"
mkdir -p "$STAGING_DIR/PyQt5"

# Locate PyQt5 inside conda environment
SITE_PKGS="$CONDA_PREFIX/lib/python3.10/site-packages"

# Verify expected build artifacts exist
if ! ls "$SITE_PKGS"/PyQt5/*.so &>/dev/null; then
  echo "[ERROR] No .so files found in $SITE_PKGS/PyQt5. Make install may have failed."
  exit 1
fi

# Copy shared objects and stubs
cp -v "$SITE_PKGS"/PyQt5/*.so "$STAGING_DIR/PyQt5/"
cp -v "$SITE_PKGS"/PyQt5/*.pyi "$STAGING_DIR/PyQt5/"
touch "$STAGING_DIR/PyQt5/__init__.py"

# Create setup.py for wheel
cd "$STAGING_DIR"
cat <<EOF > setup.py
from setuptools import setup
from setuptools.dist import Distribution

class BinaryDistribution(Distribution):
    def has_ext_modules(self):
        return True

setup(
    name="pyqt5",
    version="${PYQT_VERSION}",
    packages=["PyQt5"],
    package_data={"PyQt5": ["*.so", "*.pyi"]},
    include_package_data=True,
    distclass=BinaryDistribution,
    zip_safe=False,
)
EOF

# Build wheel
cd "$STAGING_DIR"
python3 setup.py bdist_wheel --plat-name=linux_aarch64
cp dist/pyqt5-${PYQT_VERSION}-*.whl "$WHEEL_DIR/"

# === Validate install ===
echo "[INFO] Installing wheel to validate..."
pip install --force-reinstall --no-cache-dir "$WHEEL_DIR"/pyqt5-${PYQT_VERSION}-*.whl
python3 -c "from PyQt5.QtCore import QCoreApplication; print('✅ PyQt5 ARM64 wheel installed and validated.')" when ready to proceed with integrating first build blocks.
