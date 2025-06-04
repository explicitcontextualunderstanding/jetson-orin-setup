#!/bin/bash

# ============================================================================
# build_pyqt5_arm64.sh
#
# Build PyQt5 5.10.1 from source on Jetson AGX Orin using system Qt 5.15.3 and SIP 4.19.8
# - Conda env: dfl-py310
# - Qt must be pre-installed (system-wide)
# - SIP tarball is in the "tarball/" subdirectory of the PyQt5 GitHub repo
# - All output is stored in predefined user directories
# - Supports --clean and --verbose flags
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
set -e

# === Preload sudo ===
echo "[INFO] Preloading sudo credentials..."
sudo -v

# === Directories & Versions ===
export SRC_DIR="$HOME/workspace/sources/pyqt5"
export BUILD_DIR="$HOME/workspace/builds/pyqt5_arm64_build"
export WHEEL_DIR="$HOME/wheels"
export SIP_TARBALL_PATH="tarball/sip-4.19.8.tar.gz"
export CONDA_ENV_NAME="dfl-py310"
export PYTHON_VERSION="3.10"

export CLEAN=0
export VERBOSE=0

# === CLI Options ===
for arg in "$@"; do
    case $arg in
        --clean)
            export CLEAN=1
            ;;
        --verbose)
            export VERBOSE=1
            set -x
            ;;
        *)
            echo "[ERROR] Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
 done

# === Clean mode ===
if [[ $CLEAN -eq 1 ]]; then
    echo "[INFO] Performing full cleanup..."
    conda env remove -n "$CONDA_ENV_NAME" -y || true
    rm -rf "$BUILD_DIR" "$SRC_DIR"
    echo "[INFO] Running 'make clean' in source directory..."
    if [[ -d "$SRC_DIR" ]]; then
        make -C "$SRC_DIR" clean || true
    fi
    echo "[INFO] 'make clean' completed. Cleanup done."
    # script continues after cleanup
fi

# Ensure working directory exists
cd "$HOME"

# === Qt 5.15.3 Clean-up ===
echo "[INFO] Checking for conflicting Qt 5.15 installations..."
sudo apt-get remove -y --purge qt5-default qtbase5-dev qtchooser libqt5* || true
rm -rf "$HOME/Qt/5.15."* /usr/local/Qt-5.15* 2>/dev/null || true
unset QTDIR QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH

# === Auto-install minimal Qt dev environment ===
echo "[INFO] Ensuring minimal Qt5 dev environment is available..."
sudo apt-get install -y qtbase5-dev qtchooser libqt5core5a libqt5gui5 libqt5widgets5 build-essential libgl1-mesa-dev

# === Prepare directories ===
echo "[INFO] Creating directories..."
mkdir -p "$BUILD_DIR" "$WHEEL_DIR"

# === Clone PyQt5 sources ===
if [[ ! -d "$SRC_DIR/.git" ]]; then
    echo "[INFO] Cloning PyQt5 v5.10.1 into $SRC_DIR"
    rm -rf "$SRC_DIR"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --branch 5.10.1 --depth 1 https://github.com/baoboa/pyqt5.git "$SRC_DIR"
else
    echo "[INFO] PyQt5 already cloned; fetching updates"
    cd "$SRC_DIR"
    git fetch --tags
    git checkout 5.10.1
fi

# === Create and activate conda environment ===
echo "[INFO] Creating/activating conda environment: $CONDA_ENV_NAME"
conda create -y -n "$CONDA_ENV_NAME" python=$PYTHON_VERSION
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV_NAME"

# === Install basic build tools ===
echo "[INFO] Installing build dependencies"
pip install --upgrade pip wheel setuptools

# === Extract and build SIP ===
echo "[INFO] Extracting SIP from $SRC_DIR/$SIP_TARBALL_PATH"
cd "$SRC_DIR/tarball"
tar -xzf "sip-4.19.8.tar.gz"
cd sip-4.19.8

echo "[INFO] Configuring SIP"
python configure.py --sip-module PyQt5.sip

echo "[INFO] Building SIP"
make -j$(nproc)

echo "[INFO] Installing SIP into conda environment"
make install

# === Configure and build PyQt5 ===
# Patch deprecated macros in qpycore_qstringlist.cpp for Python C-API compatibility
echo "[INFO] Patching qpycore_qstringlist.cpp macros"
sed -i -e 's/PyList_SET_ITEM/PyList_SetItem/g' \
       -e 's/PySequence_ITEM/PySequence_GetItem/g' \
    "$SRC_DIR/qpy/QtCore/qpycore_qstringlist.cpp"

# Workaround for deprecated macros in qpycore_qstringlist.cpp
export CXXFLAGS="$CXXFLAGS -DPyList_SET_ITEM=PyList_SetItem -DPySequence_ITEM=PySequence_GetItem"

echo "[INFO] Configuring PyQt5 build"
cd "$SRC_DIR"
python configure.py \
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
    --disable QtOpenGL \
    --bindir "$BUILD_DIR/bin" \
    --destdir "$BUILD_DIR/lib/python$PYTHON_VERSION/site-packages" \
    --sipdir "$BUILD_DIR/share/sip" \
    ${VERBOSE:+--verbose}

# === Patch duplicate QtGui OpenGL constants entries ===
echo "[INFO] Patching QtGui Makefile for duplicate qpyopengl_add_constants.o"
# Remove the second occurrence of qpyopengl_add_constants.o in the OBJECTS list
sed -i '0,/qpyopengl_add_constants\.o \\/{//d;}' "$SRC_DIR/QtGui/Makefile"

echo "[INFO] Building PyQt5"
make -j$(nproc)

echo "[INFO] Installing PyQt5 into staging directory"
make install

echo "[INFO] Copying SIP into staging directory"
# Ensure the SIP extension and stub are included in the wheel
cp "$CONDA_PREFIX/lib/python${PYTHON_VERSION}/site-packages/PyQt5/sip.so" \
   "$BUILD_DIR/lib/python${PYTHON_VERSION}/site-packages/PyQt5/"
cp "$CONDA_PREFIX/lib/python${PYTHON_VERSION}/site-packages/sip.pyi" \
   "$BUILD_DIR/lib/python${PYTHON_VERSION}/site-packages/"


# === Move into staging directory for wheel build ===
echo "[INFO] Changing directory to staging for wheel assembly"
cd "$BUILD_DIR/lib/python${PYTHON_VERSION}/site-packages"

# === Prepare PEP 517 build with pyproject.toml ===
echo "[INFO] Generating pyproject.toml for wheel build"
cat > pyproject.toml << 'EOF'
[build-system]
requires = ["setuptools>=40.8.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "PyQt5"
version = "5.10.1"
description = "PyQt5 modules built natively for Jetson Orin"
requires-python = ">=3.10,<3.11"
# No extra metadata; modules are under PyQt5/

[project.urls]
Home = "https://github.com/baoboa/pyqt5"
EOF

# === Build wheel via PEP517 ===
echo "[INFO] Building wheel via pyproject.toml"
python -m pip wheel . --no-deps -w "$WHEEL_DIR" --use-pep517

# Clean up pyproject.toml
rm pyproject.toml

# === Install and test the locally built wheel ===
echo "[INFO] Installing built PyQt5 wheel locally"
pip install --no-deps --no-index --find-links "$WHEEL_DIR" PyQt5

echo "[INFO] Testing PyQt5 import"
python - <<EOF
from PyQt5.QtCore import QCoreApplication
print('Import succeeded.')
EOF
