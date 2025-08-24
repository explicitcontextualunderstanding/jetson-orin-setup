#!/usr/bin/env bash
#
# Hardened minimized PyQt5 (5.15.x) build for NVIDIA Jetson (ARM64) using system Qt.
# Excludes WebEngine & other optional modules to cut build time, RAM, and footprint.
#
# Env vars:
#   PYQT_VERSION (default 5.15.10)
#   ENABLE_MULTIMEDIA=1   include QtMultimedia (default 0)
#   EXTRA_DISABLE="QtSvg QtSql"  additional disables
#   MAKE_JOBS (default 1)
#   SKIP_APT=1            skip apt dependency install
#   LOCAL_TARBALL_DIR=/dir  use local PyQt5-<ver>.tar.gz if present
#
set -euo pipefail

PYQT_VERSION="${PYQT_VERSION:-5.15.10}"
MAKE_JOBS="${MAKE_JOBS:-1}"
ENABLE_MULTIMEDIA="${ENABLE_MULTIMEDIA:-0}"
EXTRA_DISABLE="${EXTRA_DISABLE:-}"
SKIP_APT="${SKIP_APT:-0}"
LOCAL_TARBALL_DIR="${LOCAL_TARBALL_DIR:-}"

SIP_SPEC=">=6.7,<6.12"   # avoid sip 6.12.0 regression with PyQt5 configure
LOG_PREFIX="[PyQt5-MinBuild]"
export PYTHONNOUSERSITE=1

log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARNING: $*" >&2; }
err()  { echo "${LOG_PREFIX} ERROR: $*" >&2; }

command -v python >/dev/null 2>&1 || { err "Python not found"; exit 2; }
PYTHON_BIN=$(command -v python)
PYTHON_VER=$($PYTHON_BIN -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")
log "Python: $PYTHON_BIN (v$PYTHON_VER)"
[[ -n "${CONDA_PREFIX:-}" ]] && log "Conda env: $CONDA_PREFIX"

[[ "$MAKE_JOBS" != "1" ]] && warn "MAKE_JOBS>1 increases memory usage."

if [[ -r /proc/meminfo ]]; then
  MEM_AVAIL_MB=$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
  log "MemAvailable: ${MEM_AVAIL_MB} MB"
  (( MEM_AVAIL_MB < 1500 )) && warn "Low memory; stop GUI or add swap."
fi

APT_DEPS=( build-essential python3-dev qtbase5-dev qtbase5-dev-tools qtchooser qt5-qmake libqt5svg5-dev )
[[ "$ENABLE_MULTIMEDIA" == "1" ]] && APT_DEPS+=( qtmultimedia5-dev )

if [[ "$SKIP_APT" != "1" ]]; then
  log "Installing APT dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y "${APT_DEPS[@]}"
else
  log "Skipping APT install (SKIP_APT=1)"
fi

command -v qmake >/dev/null 2>&1 || { err "qmake missing after deps install"; exit 3; }

DISABLE_MODULES=(
  QtWebEngineCore QtWebEngineWidgets QtWebEngineQuick
  QtWebChannel QtWebSockets
  QtPositioning QtLocation
  QtBluetooth QtNfc QtSensors
  QtTest QtSerialPort
)
[[ "$ENABLE_MULTIMEDIA" != "1" ]] && DISABLE_MODULES+=( QtMultimedia )
if [[ -n "$EXTRA_DISABLE" ]]; then
  read -r -a EXTRA_ARR <<<"$EXTRA_DISABLE"
  DISABLE_MODULES+=("${EXTRA_ARR[@]}")
fi

log "Target PyQt5: $PYQT_VERSION"
log "Disabling: ${DISABLE_MODULES[*]}"
log "Multimedia enabled? $ENABLE_MULTIMEDIA"
log "MAKE_JOBS=$MAKE_JOBS"
log "SIP spec: $SIP_SPEC"

python - <<PY
import subprocess, sys, os
spec = os.environ['SIP_SPEC']
print(f"[PyQt5-MinBuild] Ensuring sip {spec}")
def need():
    try:
        import sip
        from packaging.specifiers import SpecifierSet
        from packaging.version import Version
        if Version(sip.__version__) not in SpecifierSet(spec):
            print(f"[PyQt5-MinBuild] sip {sip.__version__} not in {spec}; adjust.")
            return True
        return False
    except Exception:
        print("[PyQt5-MinBuild] sip missing.")
        return True
if need():
    subprocess.check_call([sys.executable,"-m","pip","install","--no-cache-dir",f"sip{spec}"])
try:
    import PyQt5.sip  # noqa
except Exception:
    print("[PyQt5-MinBuild] Installing PyQt5-sip==12.13.0")
    subprocess.check_call([sys.executable,"-m","pip","install","--no-cache-dir","PyQt5-sip==12.13.0"])
PY

python -m pip uninstall -y PyQt5 >/dev/null 2>&1 || true

WORKDIR=$(mktemp -d /tmp/pyqt5build.XXXXXX)
cleanup() {
  rc=$?
  [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
  (( rc != 0 )) && err "Build failed (exit $rc)."
  exit $rc
}
trap cleanup EXIT

log "Work dir: $WORKDIR"
pushd "$WORKDIR" >/dev/null

TARBALL="PyQt5-${PYQT_VERSION}.tar.gz"
URL="https://files.pythonhosted.org/packages/source/P/PyQt5/${TARBALL}"
if [[ -n "$LOCAL_TARBALL_DIR" && -f "$LOCAL_TARBALL_DIR/$TARBALL" ]]; then
  log "Using local tarball"
  cp "$LOCAL_TARBALL_DIR/$TARBALL" .
else
  log "Downloading $TARBALL"
  for i in 1 2 3 4; do
    if wget -q "$URL" -O "$TARBALL"; then break; fi
    warn "Download attempt $i failed; retry..."
    sleep 4
  done
  [[ -s "$TARBALL" ]] || { err "Download failed"; exit 4; }
fi

log "Extracting..."
tar xf "$TARBALL"
cd "PyQt5-${PYQT_VERSION}"

CONFIG_CMD=(
  "$PYTHON_BIN" configure.py
  --confirm-license
  --no-designer-plugin
  --no-qml-plugin
)
for m in "${DISABLE_MODULES[@]}"; do
  CONFIG_CMD+=( --disable "$m" )
done

log "Configure command:"
printf ' %q' "${CONFIG_CMD[@]}"; echo
"${CONFIG_CMD[@]}"

export MAKEFLAGS="-j${MAKE_JOBS}"
log "Building (MAKEFLAGS=$MAKEFLAGS)..."
make
log "Installing..."
make install

log "Verifying..."
python - <<PY
import importlib, sys
from PyQt5.QtCore import QT_VERSION_STR, PYQT_VERSION_STR
import PyQt5
disabled = "${DISABLE_MODULES[*]}".split()
print("Qt Version:", QT_VERSION_STR)
print("PyQt Version:", PYQT_VERSION_STR)
core_fail=[]
for core in ("QtCore","QtGui","QtWidgets"):
    try: importlib.import_module(f"PyQt5.{core}")
    except Exception as e: core_fail.append(f"{core}: {e}")
if core_fail:
    print("FAILED core imports:", core_fail); sys.exit(1)
unexpected=[]
for mod in disabled:
    try: importlib.import_module(f"PyQt5.{mod}"); unexpected.append(mod)
    except ImportError: pass
print("Unexpected disabled modules present:", unexpected if unexpected else "None (OK)")
print("Sample modules:", [m for m in dir(PyQt5) if m.startswith("Qt")][:18])
PY

popd >/dev/null
trap - EXIT
cleanup