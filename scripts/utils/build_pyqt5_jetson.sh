#!/usr/bin/env bash
#
# Minimal / hardened PyQt5 source build for Jetson (Qt 5.15.x)
# - Excludes heavy / unused modules
# - Provides deterministic version pins & manifest
# - Adds a compatibility 'sip' wrapper for PyQt5's legacy configure expectations
#
set -euo pipefail

start_epoch=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ---- Configurable Environment Variables (allow override before invoking) ----
PYQT_VERSION="${PYQT_VERSION:-5.15.10}"
MAKE_JOBS="${MAKE_JOBS:-1}"
ENABLE_MULTIMEDIA="${ENABLE_MULTIMEDIA:-0}"     # 0 = disable QtMultimedia
SKIP_APT="${SKIP_APT:-0}"
KEEP_BUILD_DIR="${KEEP_BUILD_DIR:-0}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"
USE_DIRECT_FETCH="${USE_DIRECT_FETCH:-1}"       # 1 = fetch sdist directly
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

echo "[INFO] Upgrading pip..."
pip_install pip >/dev/null

echo "[INFO] Ensuring pinned sip & PyQt5-sip..."
pip_install "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"

# Verify sipbuild + runtime module exist
"${python_cmd}" - <<'PY'
import importlib.util, sys
missing = [m for m in ("sipbuild","PyQt5.sip") if importlib.util.find_spec(m) is None]
if missing:
    print("[ERROR] Missing sip components:", missing); sys.exit(1)
print("[INFO] sip components present (runtime + builder).")
PY

# ---- SIP Compatibility Wrapper (replaces legacy 'sip' CLI expected by configure.py) ----
PYTHON_ABS="${python_cmd}"

echo "[INFO] Creating sip compatibility wrapper"
create_sip_wrapper() {
  local bin_dir="${ENV_BIN}"
  local target="${bin_dir}/sip"
  cat > "${target}" <<EOS
#!/usr/bin/env bash
# Compatibility wrapper for legacy 'sip' CLI expected by PyQt5 configure.py
if [[ "\$1" == "-V" ]]; then
  "${PYTHON_ABS}" - <<'PY'
try:
    import importlib.metadata as md
except ImportError:
    import importlib_metadata as md
def emit_version():
    try:
        v = md.version("sip")
        if not v or not v[0].isdigit():
            raise ValueError("Non-numeric start")
        print(v); return
    except Exception:
        pass
    try:
        import sipbuild
        v = getattr(sipbuild, "__version__", None)
        if v and v[0].isdigit():
            print(v); return
    except Exception:
        pass
    # Final fallback (prefer failing instead; adjust if desired)
    print("6.0.0")
emit_version()
PY
  exit 0
fi
exec sip-build "\$@"
EOS
  chmod +x "${target}"
}

validate_sip_wrapper() {
  if ! command -v sip >/dev/null 2>&1; then
    echo "[ERROR] 'sip' not found after wrapper creation." >&2
    return 1
  fi
  local v
  v="$(sip -V 2>/dev/null || true)"
  if [[ "${v}" =~ ^[0-9]+(\.[0-9]+){1,2}([A-Za-z0-9.+-]*)?$ ]]; then
    echo "[INFO] sip wrapper version OK: ${v}"
    return 0
  else
    echo "[ERROR] sip -V produced unexpected output: '${v}'" >&2
    echo "[DEBUG] Wrapper path: $(command -v sip)" >&2
    return 1
  fi
}

create_sip_wrapper
if ! validate_sip_wrapper; then
  echo "[HINT] Try: pip install --upgrade --force-reinstall sip" >&2
  exit 10
fi

# ---- Optional system dependencies (Qt headers, tools) ----
if [[ "${SKIP_APT}" != "1" ]]; then
  if command -v apt-get >/dev/null; then
    echo "[INFO] Verifying Qt build deps via apt-get."
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends \
      qtbase5-dev qttools5-dev-tools qtdeclarative5-dev \
      build-essential libgl1-mesa-dev libxkbcommon-x11-0 python3-dev
  else
    echo "[WARN] apt-get not found; skipping system deps install."
  fi
else
  echo "[INFO] SKIP_APT=1: skipping apt dependency install."
fi

# ---- qmake detection ----
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

# ---- Build workspace setup ----
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

# ---- Fetch PyQt5 source ----
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

# ---- Disable unwanted modules ----
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

echo "[INFO] Running configure.py"
set -x
if ! "${python_cmd}" configure.py \
      --confirm-license \
      --qmake "${QMAKE}" \
      --no-designer-plugin \
      --no-qml-plugin \
      "${CONFIGURE_ARGS[@]}"; then
  set +x
  echo "[ERROR] configure.py failed (after sip wrapper + qmake)." >&2
  echo "[HINT] Inspect ${TMP_BUILD}/${SRC_DIR}/config.log (if present)." >&2
  exit 20
fi
set +x

# ---- Build & Install ----
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

popd >/dev/null   # out of SRC_DIR
popd >/dev/null   # out of TMP_BUILD

# ---- Negative Import Validation ----
echo "[INFO] Running negative import validation"
VALIDATION_SCRIPT="$(mktemp "${BUILD_PARENT}/validate_pyqt_XXXX.py")"
cat > "${VALIDATION_SCRIPT}" <<'PY'
from PyQt5 import QtCore, QtGui, QtWidgets
print("Qt Version:", QtCore.QT_VERSION_STR)
print("PyQt Version:", QtCore.PYQT_VERSION_STR)
disabled = [
    "QtWebEngineWidgets","QtWebEngineCore","QtWebEngineQuick","QtWebChannel",
    "QtWebSockets","QtPositioning","QtLocation","QtBluetooth","QtNfc",
    "QtSensors","QtSerialPort","QtTest"
]
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

# Ensure runtime sees the same ENABLE_MULTIMEDIA
ENABLE_MULTIMEDIA="${ENABLE_MULTIMEDIA}" "${python_cmd}" "${VALIDATION_SCRIPT}" || {
  echo "[ERROR] Validation failed." >&2
  exit 50
}

# ---- Manifest Generation ----
echo "[INFO] Generating manifest"
SITE_PKGS="$(${python_cmd} -c 'import site,sys; print(next(p for p in site.getsitepackages() if "site-packages" in p))')"
MANIFEST="${BUILD_PARENT}/pyqt5_manifest_$(date +%Y%m%d%H%M%S).txt"
find "${SITE_PKGS}/PyQt5" -type f -print | LC_ALL=C sort > "${MANIFEST}"
( command -v sha256sum >/dev/null && sha256sum "${MANIFEST}" || shasum -a 256 "${MANIFEST}" ) > "${MANIFEST}.sha256"

# ---- Optional Size Report ----
SIZE_FILE_COUNT=$(wc -l < "${MANIFEST}")
PKG_SIZE=$(du -sh "${SITE_PKGS}/PyQt5" | awk '{print $1}')
echo "[INFO] Installed file count: ${SIZE_FILE_COUNT}"
echo "[INFO] Installed PyQt5 directory size: ${PKG_SIZE}"

duration=$(( $(date +%s) - start_epoch ))
echo "[INFO] Build & validation complete in ${duration}s"
echo "[INFO] Manifest: ${MANIFEST}"
echo "[INFO] Manifest hash: $(cut -d' ' -f1 "${MANIFEST}.sha256")"
echo "[INFO] Done."
exit 0