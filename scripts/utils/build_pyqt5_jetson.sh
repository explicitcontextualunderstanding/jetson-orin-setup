#!/usr/bin/env bash
#
# Hardened minimal PyQt5 build script for Jetson Orin (Qt 5.15.x)
#
# Environment Variables:
#   PYQT_VERSION        PyQt5 version to build (default 5.15.10)
#   MAKE_JOBS           Parallel make jobs (default 1 for memory safety)
#   ENABLE_MULTIMEDIA   If "1", DO NOT disable QtMultimedia (default 0 disables it)
#   SKIP_APT            If "1", skip apt dependency install (default 0)
#   PIP_INDEX_URL       Override primary pip index (optional)
#   EXTRA_PIP_ARGS      Extra pip arguments (optional)
#   KEEP_BUILD_DIR      If "1", keep temp build directory (default 0)
#
# Exit Codes:
#   10 preflight failure
#   20 configure failure
#   30 build failure
#   40 install failure
#   50 validation failure
#   0  success
#
set -euo pipefail

start_epoch=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PYQT_VERSION="${PYQT_VERSION:-5.15.10}"
MAKE_JOBS="${MAKE_JOBS:-1}"
ENABLE_MULTIMEDIA="${ENABLE_MULTIMEDIA:-0}"
SKIP_APT="${SKIP_APT:-0}"
KEEP_BUILD_DIR="${KEEP_BUILD_DIR:-0}"

export PYTHONNOUSERSITE=1

echo "[INFO] PyQt5 version: ${PYQT_VERSION}"
echo "[INFO] MAKE_JOBS=${MAKE_JOBS}"
echo "[INFO] ENABLE_MULTIMEDIA=${ENABLE_MULTIMEDIA}"
echo "[INFO] SKIP_APT=${SKIP_APT}"

python_cmd="$(command -v python || true)"
if [[ -z "${python_cmd}" ]]; then
  echo "[ERROR] Python not found in PATH." >&2
  exit 10
fi
echo "[INFO] Using python: ${python_cmd}"

# Preflight: confirm builder/runtime sip presence or install pins.
echo "[INFO] Ensuring pinned sip + PyQt5-sip present."
pip_base=( "${python_cmd}" -m pip ${EXTRA_PIP_ARGS:-} )
if [[ -n "${PIP_INDEX_URL:-}" ]]; then
  pip_base+=( "--index-url" "${PIP_INDEX_URL}" )
fi

# Ensure pip is current
"${pip_base[@]}" install --upgrade pip >/dev/null

# Install pins explicitly (force reinstall to avoid incompatible versions)
"${pip_base[@]}" install --no-cache-dir --upgrade "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"

python - <<'PY'
import importlib.util, sys
missing = []
for name in ("sipbuild", "PyQt5.sip"):
    if importlib.util.find_spec(name) is None:
        missing.append(name)
if missing:
    print("[ERROR] Missing required sip components:", missing)
    sys.exit(1)
print("[INFO] sip components present.")
PY
if [[ $? -ne 0 ]]; then
  exit 10
fi

# Optional apt dependencies (assumes Ubuntu-based Jetson)
if [[ "${SKIP_APT}" != "1" ]]; then
  if command -v apt-get >/dev/null; then
    echo "[INFO] Installing system build dependencies via apt-get."
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends \
      qtbase5-dev qttools5-dev-tools qtdeclarative5-dev \
      build-essential libgl1-mesa-dev libxkbcommon-x11-0 \
      python3-dev
  else
    echo "[WARN] apt-get not found; skipping system dependency installation."
  fi
else
  echo "[INFO] SKIP_APT=1: skipping apt dependencies."
fi

# Create temp build dir
BUILD_PARENT="${PROJECT_ROOT}/build_artifacts"
mkdir -p "${BUILD_PARENT}"
TMP_BUILD="$(mktemp -d "${BUILD_PARENT}/pyqt5-build-XXXXXX")"

cleanup() {
  if [[ "${KEEP_BUILD_DIR}" != "1" ]]; then
    rm -rf "${TMP_BUILD}"
  else
    echo "[INFO] Keeping build dir: ${TMP_BUILD}"
  fi
}
trap cleanup EXIT

pushd "${TMP_BUILD}" >/dev/null

echo "[INFO] Downloading PyQt5 source (version ${PYQT_VERSION})"
# Force source distribution (avoid wheels)
if ! "${pip_base[@]}" download --no-binary=:all: "PyQt5==${PYQT_VERSION}"; then
  echo "[ERROR] Failed to download PyQt5 sdist." >&2
  exit 10
fi
sdist_tar=$(ls PyQt5-*.tar.* | head -n1 || true)
if [[ -z "${sdist_tar}" ]]; then
  echo "[ERROR] PyQt5 source archive not found." >&2
  exit 10
fi
tar xf "${sdist_tar}"
SRC_DIR="$(find . -maxdepth 1 -type d -name "PyQt5-${PYQT_VERSION}" -print -quit)"
if [[ -z "${SRC_DIR}" ]]; then
  echo "[ERROR] Extracted source directory not located." >&2
  exit 10
fi

pushd "${SRC_DIR}" >/dev/null

# Assemble disable list
DISABLE_MODULES=(
  QtWebEngineCore
  QtWebEngineWidgets
  QtWebEngineQuick
  QtWebChannel
  QtWebSockets
  QtPositioning
  QtLocation
  QtBluetooth
  QtNfc
  QtSensors
  QtSerialPort
  QtTest
)

if [[ "${ENABLE_MULTIMEDIA}" != "1" ]]; then
  DISABLE_MODULES+=( QtMultimedia )
else
  echo "[INFO] Retaining QtMultimedia."
fi

echo "[INFO] Disabling modules: ${DISABLE_MODULES[*]}"

CONFIGURE_ARGS=()
for m in "${DISABLE_MODULES[@]}"; do
  CONFIGURE_ARGS+=( --disable "${m}" )
done

# Conservative: we rely on system Qt discoverable via pkg-config/env
echo "[INFO] Running configure.py"
set -x
if ! "${python_cmd}" configure.py \
      --confirm-license \
      --no-designer-plugin \
      --no-qml-plugin \
      --sip-module PyQt5.sip \
      "${CONFIGURE_ARGS[@]}"; then
  set +x
  echo "[ERROR] configure.py failed." >&2
  exit 20
fi
set +x

echo "[INFO] Building (jobs=${MAKE_JOBS})"
if ! make -j"${MAKE_JOBS}"; then
  echo "[ERROR] Build failed." >&2
  exit 30
fi

echo "[INFO] Installing"
if ! make install; then
  echo "[ERROR] Installation failed." >&2
  exit 40
fi

popd >/dev/null  # out of source dir
popd >/dev/null  # out of tmp build

echo "[INFO] Running negative import validation"
VALIDATION_SCRIPT="$(mktemp "${BUILD_PARENT}/validate_pyqt_XXXX.py")"
cat > "${VALIDATION_SCRIPT}" <<'PY'
from PyQt5 import QtCore, QtGui, QtWidgets
print("Qt Version:", QtCore.QT_VERSION_STR)
print("PyQt Version:", QtCore.PYQT_VERSION_STR)
disabled = [
    "QtWebEngineWidgets","QtWebEngineCore","QtWebEngineQuick","QtWebChannel",
    "QtWebSockets","QtPositioning","QtLocation","QtBluetooth","QtNfc",
    "QtSensors","QtSerialPort","QtTest","QtMultimedia"
]
present=[]
for mod in disabled:
    try:
        __import__("PyQt5."+mod)
        present.append(mod)
    except ImportError:
        pass
if present:
    print("Unexpected modules present:", present)
    raise SystemExit(1)
print("All excluded modules correctly absent.")
PY

if ! "${python_cmd}" "${VALIDATION_SCRIPT}"; then
  echo "[ERROR] Validation failed." >&2
  exit 50
fi

echo "[INFO] Generating file manifest + hash"
SITE_PKGS="$(${python_cmd} -c 'import site,sys; print(next(p for p in site.getsitepackages() if "site-packages" in p))')"
MANIFEST="${BUILD_PARENT}/pyqt5_manifest_$(date +%Y%m%d%H%M%S).txt"
find "${SITE_PKGS}/PyQt5" -type f -print | LC_ALL=C sort > "${MANIFEST}"
sha256sum "${MANIFEST}" > "${MANIFEST}.sha256" 2>/dev/null || shasum -a 256 "${MANIFEST}" > "${MANIFEST}.sha256"

duration=$(( $(date +%s) - start_epoch ))
echo "[INFO] Build & validation complete in ${duration}s"
echo "[INFO] Manifest: ${MANIFEST}"
echo "[INFO] Done."

exit 0