#!/usr/bin/env bash
#
# Hardened minimal PyQt5 build script for Jetson Orin (Qt 5.15.x)
# Fixes: remove unsupported --sip-module, add sip shim if missing, qmake preflight.
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
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"
# Default to direct fetch now for reliability
USE_DIRECT_FETCH="${USE_DIRECT_FETCH:-1}"

: "${PIP_INDEX_URL:=https://pypi.org/simple}"
export PIP_INDEX_URL
unset PIP_EXTRA_INDEX_URL || true
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONNOUSERSITE=1

echo "[INFO] PyQt5 version: ${PYQT_VERSION}"
echo "[INFO] MAKE_JOBS=${MAKE_JOBS}"
echo "[INFO] ENABLE_MULTIMEDIA=${ENABLE_MULTIMEDIA}"
echo "[INFO] SKIP_APT=${SKIP_APT}"
echo "[INFO] PIP_INDEX_URL=${PIP_INDEX_URL}"
echo "[INFO] DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT}"
echo "[INFO] USE_DIRECT_FETCH=${USE_DIRECT_FETCH}"

python_cmd="$(command -v python || true)"
if [[ -z "${python_cmd}" ]]; then
  echo "[ERROR] Python not found in PATH." >&2
  exit 10
fi
ENV_BIN="$(dirname "${python_cmd}")"
echo "[INFO] Using python: ${python_cmd}"

if [[ "${CONDA_DEFAULT_ENV:-}" == "base" ]]; then
  echo "[WARN] CONDA_DEFAULT_ENV=base; expected a clean build env (e.g. pyqtbuild)."
fi

pip_install() {
  "${python_cmd}" -m pip install --no-cache-dir --upgrade \
    ${PIP_INDEX_URL:+--index-url "${PIP_INDEX_URL}"} "$@"
}

# Upgrade pip
pip_install pip >/dev/null

echo "[INFO] Ensuring pinned sip & PyQt5-sip."
pip_install "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"

"${python_cmd}" - <<'PY'
import importlib.util, sys
missing = [m for m in ("sipbuild","PyQt5.sip") if importlib.util.find_spec(m) is None]
if missing:
    print("[ERROR] Missing sip components:", missing); sys.exit(1)
print("[INFO] sip components present (runtime + builder).")
PY

# Ensure sip executable (configure.py expects 'sip')
ensure_sip_exe() {
  if command -v sip >/dev/null 2>&1; then
    echo "[INFO] Found existing sip executable: $(command -v sip)"
    return 0
  fi
  if command -v sip-build >/dev/null 2>&1; then
    echo "[INFO] Creating sip shim -> sip-build"
    ln -sf "$(command -v sip-build)" "${ENV_BIN}/sip"
    chmod +x "${ENV_BIN}/sip"
    return 0
  fi
  echo "[ERROR] Neither sip nor sip-build found on PATH." >&2
  return 1
}

if ! ensure_sip_exe; then
  echo "[HINT] Try: python -m pip install --force-reinstall sip" >&2
  exit 10
fi

# Optional system deps
if [[ "${SKIP_APT}" != "1" ]]; then
  if command -v apt-get >/dev/null; then
    echo "[INFO] Installing Qt build deps via apt-get."
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends \
      qtbase5-dev qttools5-dev-tools qtdeclarative5-dev \
      build-essential libgl1-mesa-dev libxkbcommon-x11-0 python3-dev
  else
    echo "[WARN] apt-get not found; skipping system deps."
  fi
else
  echo "[INFO] SKIP_APT=1: skipping apt dependency install."
fi

# qmake detection
QMAKE_CANDIDATES=(
  "$(command -v qmake || true)"
  "/usr/lib/qt5/bin/qmake"
  "/usr/lib/aarch64-linux-gnu/qt5/bin/qmake"
  "/usr/bin/qmake"
)
QMAKE=""
for c in "${QMAKE_CANDIDATES[@]}"; do
  [[ -x "${c}" ]] && QMAKE="${c}" && break || true
done
if [[ -z "${QMAKE}" ]]; then
  echo "[ERROR] qmake not found. Install qtbase5-dev or specify QMAKE=/path/to/qmake." >&2
  [[ "${SKIP_APT}" == "1" ]] && echo "[HINT] Re-run without SKIP_APT=1 to auto-install Qt dev packages." >&2
  exit 10
fi
echo "[INFO] Using qmake: ${QMAKE}"

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

direct_fetch() {
  echo "[INFO] Fetching PyQt5 sdist directly."
  local py_url
  py_url="$("${python_cmd}" - <<PY
import json,urllib.request,sys
ver="${PYQT_VERSION}"
data=json.load(urllib.request.urlopen(f"https://pypi.org/pypi/PyQt5/{ver}/json"))
for f in data["urls"]:
    if f["packagetype"]=="sdist" and f["filename"].endswith(".tar.gz"):
        print(f["url"]); break
PY
)"
  if [[ -z "${py_url}" ]]; then
    echo "[ERROR] Could not resolve sdist URL from PyPI JSON." >&2
    return 1
  fi
  echo "[INFO] sdist URL: ${py_url}"
  curl -L -o "PyQt5-${PYQT_VERSION}.tar.gz" "${py_url}"
}

pip_fetch() {
  echo "[INFO] Attempting pip download (timeout ${DOWNLOAD_TIMEOUT}s)."
  local cmd=( "${python_cmd}" -m pip download --no-binary=:all: --no-deps "PyQt5==${PYQT_VERSION}" )
  if command -v timeout >/dev/null; then
    timeout "${DOWNLOAD_TIMEOUT}" "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
}

dl_start=$(date +%s)
if [[ "${USE_DIRECT_FETCH}" == "1" ]]; then
  direct_fetch || { echo "[ERROR] Direct fetch failed." >&2; exit 10; }
else
  if ! pip_fetch; then
    echo "[WARN] pip fetch failed/froze; falling back to direct fetch."
    direct_fetch || { echo "[ERROR] Both fetch strategies failed." >&2; exit 10; }
  fi
fi
dl_end=$(date +%s)
echo "[INFO] Download phase duration: $((dl_end - dl_start))s"

sdist_tar="PyQt5-${PYQT_VERSION}.tar.gz"
if [[ ! -f "${sdist_tar}" ]]; then
  sdist_tar=$(ls PyQt5-"${PYQT_VERSION}".tar.* 2>/dev/null | head -n1 || true)
fi
if [[ -z "${sdist_tar}" || ! -f "${sdist_tar}" ]]; then
  echo "[ERROR] PyQt5 source archive missing after fetch." >&2
  exit 10
fi

tar xf "${sdist_tar}"
SRC_DIR="PyQt5-${PYQT_VERSION}"
[[ -d "${SRC_DIR}" ]] || SRC_DIR="$(find . -maxdepth 1 -type d -name 'PyQt5-*' -print -quit)"
if [[ -z "${SRC_DIR}" || ! -d "${SRC_DIR}" ]]; then
  echo "[ERROR] Extracted PyQt5 source directory not found." >&2
  exit 10
fi

pushd "${SRC_DIR}" >/dev/null

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
fi

echo "[INFO] Disabling modules: ${DISABLE_MODULES[*]}"

CONFIGURE_ARGS=()
for m in "${DISABLE_MODULES[@]}"; do
  CONFIGURE_ARGS+=( --disable "${m}" )
done

echo "[INFO] Running configure.py (first attempt)"
set -x
if ! "${python_cmd}" configure.py \
      --confirm-license \
      --qmake "${QMAKE}" \
      --no-designer-plugin \
      --no-qml-plugin \
      "${CONFIGURE_ARGS[@]}"; then
  set +x
  echo "[ERROR] configure.py failed (after sip shim + qmake)."
  echo "[HINT] Inspect ${TMP_BUILD}/${SRC_DIR}/config.log (if present) for details." >&2
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

popd >/dev/null
popd >/dev/null

echo "[INFO] Running negative import validation"
VALIDATION_SCRIPT="$(mktemp "${BUILD_PARENT}/validate_pyqt_XXXX.py")"
cat > "${VALIDATION_SCRIPT}" <<PY
from PyQt5 import QtCore, QtGui, QtWidgets
print("Qt Version:", QtCore.QT_VERSION_STR)
print("PyQt Version:", QtCore.PYQT_VERSION_STR)
disabled = [
    "QtWebEngineWidgets","QtWebEngineCore","QtWebEngineQuick","QtWebChannel",
    "QtWebSockets","QtPositioning","QtLocation","QtBluetooth","QtNfc",
    "QtSensors","QtSerialPort","QtTest"
]
# Only test Multimedia if it was disabled
import os
if os.environ.get("ENABLE_MULTIMEDIA","0") != "1":
    disabled.append("QtMultimedia")
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

echo "[INFO] Generating manifest"
SITE_PKGS="$(${python_cmd} -c 'import site,sys; print(next(p for p in site.getsitepackages() if "site-packages" in p))')"
MANIFEST="${BUILD_PARENT}/pyqt5_manifest_$(date +%Y%m%d%H%M%S).txt"
find "${SITE_PKGS}/PyQt5" -type f -print | LC_ALL=C sort > "${MANIFEST}"
( command -v sha256sum >/dev/null && sha256sum "${MANIFEST}" || shasum -a 256 "${MANIFEST}" ) > "${MANIFEST}.sha256"

duration=$(( $(date +%s) - start_epoch ))
echo "[INFO] Build & validation complete in ${duration}s"
echo "[INFO] Manifest: ${MANIFEST}"
echo "[INFO] Done."
exit 0