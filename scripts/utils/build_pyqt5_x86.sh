#!/bin/bash

# ============================================================================
# build_pyqt5_wheel.sh
#
# Build script to compile PyQt5 version 5.10.1 as a wheel from source tarball
# using the official release tarballs placed in:
#   ~/workspace/sources/pyqt5/PyQt5/tarball/
#     - PyQt5_gpl-5.10.1.tar.gz
#     - sip-4.19.8.tar.gz
#
# Target platform: Ubuntu 22.04 x86_64 (e.g. under WSL2)
#
# This script supports:
#   --clean   : Removes previous build and logs
#   --verbose : Enables verbose output
#
# Output:
#   - Wheel saved in:     ~/wheels/
#   - Build logs in:      ~/workspace/builds/pyqt5_wheel_build/build_pyqt5.log
#
# ============================================================================

set -e

# === Variables ===
PYQT_VERSION="5.10.1"
SIP_VERSION="4.19.8"
TARBALL_DIR="$HOME/workspace/sources/pyqt5/PyQt5/tarball"
SRC_DIR="$HOME/workspace/sources/pyqt5"
BUILD_DIR="$HOME/workspace/builds/pyqt5_wheel_build"
WHEEL_DIR="$HOME/wheels"
LOG_FILE="$BUILD_DIR/build_pyqt5.log"
CLEAN=false
VERBOSE=false
QMAKE_BIN="$(which qmake || true)"

# === Parse options ===
for arg in "$@"; do
  case $arg in
    --clean)
      CLEAN=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
  esac
  shift
done

# === Prepare environment ===
mkdir -p "$BUILD_DIR" "$WHEEL_DIR"
cd "$BUILD_DIR"

# === Logging setup ===
exec > >(tee "$LOG_FILE") 2>&1
if $VERBOSE; then
  set -x
fi

# === Qt 5.15.3 Clean-up ===
echo "[INFO] Checking for conflicting Qt 5.15 installations..."
sudo apt-get remove -y --purge qt5-default qtbase5-dev qtchooser libqt5* || true
rm -rf "$HOME/Qt/5.15."* /usr/local/Qt-5.15* 2>/dev/null || true
unset QTDIR QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH

# === Auto-install minimal Qt dev environment ===
# Optional: install extra modules to enable QML, WebKit, Svg, Designer, etc.
# sudo apt-get install -y qml-module-qtquick-controls qml-module-qtquick2 \
#   libqt5webkit5-dev libqt5xmlpatterns5-dev qttools5-dev qttools5-dev-tools \
#   libqt5svg5-dev qml-module-qtquick-controls2 qml-module-qtquick-templates2
# Optional: install extra modules to enable WebKit, XmlPatterns, Designer
# sudo apt-get install -y libqt5webkit5-dev libqt5xmlpatterns5-dev qttools5-dev qttools5-dev-tools
echo "[INFO] Ensuring minimal Qt5 dev environment is available..."
# sudo apt-get update
sudo apt-get install -y qtbase5-dev qtchooser libqt5core5a libqt5gui5 libqt5widgets5 build-essential libgl1-mesa-dev

# === Clean mode ===
if $CLEAN; then
  echo "[INFO] Cleaning previous build..."
  rm -rf "$BUILD_DIR"/* "$WHEEL_DIR"/PyQt5-${PYQT_VERSION}-*.whl "$LOG_FILE"
  echo "[INFO] Clean complete."
  exit 0
fi

# === Extract SIP tarball ===
echo "[INFO] Extracting SIP ${SIP_VERSION}..."
rm -rf sip-${SIP_VERSION} && tar -xf "$TARBALL_DIR/sip-${SIP_VERSION}.tar.gz" -C "$BUILD_DIR"
cd "$BUILD_DIR/sip-${SIP_VERSION}"

# === Build and install SIP ===
echo "[INFO] Building SIP..."
python3 configure.py
make -j$(nproc)
sudo make install

# === Extract PyQt5 tarball ===
echo "[INFO] Extracting PyQt5 ${PYQT_VERSION}..."
cd "$BUILD_DIR"
rm -rf PyQt5_gpl-${PYQT_VERSION} && tar -xf "$TARBALL_DIR/PyQt5_gpl-${PYQT_VERSION}.tar.gz"
cd PyQt5_gpl-${PYQT_VERSION}

# === Validate qmake path ===
QMAKE_BIN="$(which qmake || true)"
if [ -z "$QMAKE_BIN" ]; then
  echo "[ERROR] qmake still not found. Qt development tools may not have been installed correctly."
  exit 1
fi

# === Configure PyQt5 ===
echo "[INFO] Configuring PyQt5 with qmake at: $QMAKE_BIN..."
python3 configure.py --confirm-license --sip /usr/bin/sip --verbose \
  --disable Enginio \
  --disable QtBluetooth \
  --disable QtDesigner \
  --disable QtLocation \
  --disable QtMacExtras \
  --disable QtNfc \
  --disable QtPositioning \
  --disable QtQml \
  --disable QtQuick \
  --disable QtQuickWidgets \
  --disable QtSensors \
  --disable QtSerialPort \
  --disable QtSvg \
  --disable QtWebChannel \
  --disable QtWebEngineWidgets \
  --disable QtWebKit \
  --disable QtWebKitWidgets \
  --disable QtWebSockets \
  --disable QtWinExtras \
  --disable QtX11Extras \
  --disable QtXmlPatterns \
  --disable QtTest

# === Build and install PyQt5 ===
echo "[INFO] Building PyQt5..."
make -j$(nproc)

# === Build wheel ===
STAGING_DIR="$BUILD_DIR/wheel_staging"
mkdir -p "$STAGING_DIR/PyQt5"

# Detect site-packages path
if [ -d "/usr/local/lib/python3.10/dist-packages/PyQt5" ]; then
  SITE_PKGS="/usr/local/lib/python3.10/dist-packages"
elif [ -d "/usr/lib/python3/dist-packages/PyQt5" ]; then
  SITE_PKGS="/usr/lib/python3/dist-packages"
else
  echo "[WARNING] Could not find PyQt5 in common paths. Listing site-packages:"
  find /usr -type d -name "PyQt5" 2>/dev/null || true
  echo "[ERROR] PyQt5 install not found in expected locations."
  exit 1
fi

# Copy .so and .pyi files
cp -v "$SITE_PKGS"/PyQt5/*.so "$STAGING_DIR/PyQt5/"
cp -v "$SITE_PKGS"/PyQt5/*.pyi "$STAGING_DIR/PyQt5/"
touch "$STAGING_DIR/PyQt5/__init__.py"

# Create setup.py
cat <<EOF > "$STAGING_DIR/setup.py"
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
python3 setup.py bdist_wheel
cp dist/pyqt5-${PYQT_VERSION}-*.whl "$WHEEL_DIR/"

# === Install locally ===
echo "[INFO] Installing PyQt5 wheel from $WHEEL_DIR..."
pip install --force-reinstall "$WHEEL_DIR"/pyqt5-${PYQT_VERSION}-*.whl

# === Validation ===
echo "[INFO] Verifying PyQt5 installation..."
python3 -c "from PyQt5.QtCore import QCoreApplication; print('✅ PyQt5 installed and working.')"
