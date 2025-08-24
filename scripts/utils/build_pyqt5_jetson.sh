#!/usr/bin/env bash
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
[[ -z "${python_cmd}" ]] && { echo "[ERROR] python not found"; exit 10; }
ENV_BIN="$(dirname "${python_cmd}")"

pip_install() {
  "${python_cmd}" -m pip install --no-cache-dir --upgrade \
    ${PIP_INDEX_URL:+--index-url "${PIP_INDEX_URL}"} "$@"
}

echo "[INFO] Upgrading pip..."
pip_install pip >/dev/null

echo "[INFO] Ensuring pinned sip & PyQt5-sip..."
pip_install "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"

# Enforce sip version in range before proceeding
"${python_cmd}" - <<'PY'
import sys
try:
    import importlib.metadata as md
except ImportError:
    import importlib_metadata as md
v = md.version("sip")
from packaging.version import Version
if not (Version("6.7.0") <= Version(v) < Version("6.12.0")):
    print(f"[ERROR] Installed sip {v} outside required range >=6.7,<6.12. Reinstall exact 6.11.1.")
    sys.exit(2)
print("[INFO] sip version acceptable:", v)
PY
rc=$?
if [[ $rc -eq 2 ]]; then
  echo "[INFO] Reinstalling sip==6.11.1"
  pip_install 'sip==6.11.1'
fi

"${python_cmd}" - <<'PY'
import importlib.util, sys
missing=[m for m in ("sipbuild","PyQt5.sip") if importlib.util.find_spec(m) is None]
if missing:
    print("[ERROR] Missing sip components:", missing); sys.exit(1)
print("[INFO] sip components present.")
PY

echo "[INFO] Creating sip compatibility wrapper"
create_sip_wrapper() {
  local target="${ENV_BIN}/sip"
  cat > "${target}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/tmp/sip_wrapper.log"
if [[ "\${1:-}" == "-V" ]]; then
  if [[ -n "\${SIP_VERSION_FORCE:-}" ]]; then
    python - <<'PY'
import os,re
v=os.environ.get("SIP_VERSION_FORCE","")
nums=re.findall(r'\d+',v)
while len(nums)<3: nums.append('0')
print("{}.{}.{}".format(*nums[:3]))
PY
    exit 0
  fi
  "${python_cmd}" - <<'PY'
try:
    import importlib.metadata as md
except ImportError:
    import importlib_metadata as md
import re
raw=None
try:
    raw=md.version("sip")
except Exception:
    pass
if not raw:
    try:
        import sipbuild
        raw=getattr(sipbuild,"__version__",None)
    except Exception:
        raw=None
if not raw:
    raw="6.11.1"
nums=re.findall(r'\d+',raw)
while len(nums)<3: nums.append('0')
print("{}.{}.{}".format(*nums[:3]))
PY
  exit 0
fi
echo "\$(date +%FT%T) ARGS: \$*" >> "\${LOG_FILE}" 2>&1
exec sip-build "\$@"
EOF
  chmod +x "${target}"
}

validate_sip_wrapper() {
  local v
  v="$(sip -V 2>/dev/null || true)"
  echo "[DEBUG] sip -V output: '${v}'"
  [[ "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "[ERROR] Bad sip -V output: ${v}"; return 1; }
  echo "[INFO] sip wrapper version OK: ${v}"
}

create_sip_wrapper
validate_sip_wrapper || { echo "[ERROR] Wrapper creation failed"; exit 10; }

# qmake detection
QMAKE_CANDIDATES=( "$(command -v qmake || true)" "/usr/lib/qt5/bin/qmake" "/usr/lib/aarch64-linux-gnu/qt5/bin/qmake" "/usr/bin/qmake" )
QMAKE=""
for c in "${QMAKE_CANDIDATES[@]}"; do [[ -x "${c}" ]] && QMAKE="${c}" && break || true; done
[[ -z "${QMAKE}" ]] && { echo "[ERROR] qmake not found"; exit 10; }
echo "[INFO] Using qmake: ${QMAKE}"

BUILD_PARENT="${PROJECT_ROOT}/build_artifacts"
mkdir -p "${BUILD_PARENT}"
TMP_BUILD="$(mktemp -d "${BUILD_PARENT}/pyqt5-build-XXXXXX")"
cleanup() { [[ "${KEEP_BUILD_DIR}" != "1" ]] && rm -rf "${TMP_BUILD}" || echo "[INFO] Keeping build dir: ${TMP_BUILD}"; }
trap cleanup EXIT
pushd "${TMP_BUILD}" >/dev/null

direct_fetch() {
  echo "[INFO] Fetching PyQt5 sdist directly."
  local py_url
  py_url="$("${python_cmd}" - <<PY
import json,urllib.request
ver="${PYQT_VERSION}"
data=json.load(urllib.request.urlopen(f"https://pypi.org/pypi/PyQt5/{ver}/json"))
for f in data["urls"]:
    if f["packagetype"]=="sdist" and f["filename"].endswith(".tar.gz"):
        print(f["url"]); break
PY
)"
  [[ -z "${py_url}" ]] && { echo "[ERROR] Could not resolve sdist URL"; return 1; }
  echo "[INFO] sdist URL: ${py_url}"
  curl -L -o "PyQt5-${PYQT_VERSION}.tar.gz" "${py_url}"
}
pip_fetch() {
  echo "[INFO] Attempting pip download (timeout ${DOWNLOAD_TIMEOUT}s)."
  local cmd=( "${python_cmd}" -m pip download --no-binary=:all: --no-deps "PyQt5==${PYQT_VERSION}" )
  if command -v timeout >/dev/null; then timeout "${DOWNLOAD_TIMEOUT}" "${cmd[@]}"; else "${cmd[@]}"; fi
}

dl_start=$(date +%s)
if [[ "${USE_DIRECT_FETCH}" == "1" ]]; then direct_fetch || { echo "[ERROR] Direct fetch failed"; exit 10; }
else pip_fetch || { echo "[WARN] pip fetch failed; falling back"; direct_fetch || { echo "[ERROR] Both fetch methods failed"; exit 10; }; }
fi
dl_end=$(date +%s)
echo "[INFO] Download phase duration: $((dl_end - dl_start))s"

sdist_tar="PyQt5-${PYQT_VERSION}.tar.gz"
[[ -f "${sdist_tar}" ]] || sdist_tar="$(ls PyQt5-"${PYQT_VERSION}".tar.* 2>/dev/null | head -n1 || true)"
[[ -f "${sdist_tar}" ]] || { echo "[ERROR] Source archive missing"; exit 10; }

tar xf "${sdist_tar}"
SRC_DIR="PyQt5-${PYQT_VERSION}"
[[ -d "${SRC_DIR}" ]] || SRC_DIR="$(find . -maxdepth 1 -type d -name 'PyQt5-*' -print -quit)"
[[ -d "${SRC_DIR}" ]] || { echo "[ERROR] Source dir not found"; exit 10; }

pushd "${SRC_DIR}" >/dev/null

DISABLE_MODULES=( QtWebEngineCore QtWebEngineWidgets QtWebEngineQuick QtWebChannel QtWebSockets QtPositioning QtLocation QtBluetooth QtNfc QtSensors QtSerialPort QtTest )
[[ "${ENABLE_MULTIMEDIA}" != "1" ]] && DISABLE_MODULES+=( QtMultimedia )
echo "[INFO] Disabling modules: ${DISABLE_MODULES[*]}"

CONFIGURE_ARGS=()
for m in "${DISABLE_MODULES[@]}"; do CONFIGURE_ARGS+=( --disable "${m}" ); done

echo "[INFO] Running configure.py"
set -x
if ! "${python_cmd}" configure.py --confirm-license --qmake "${QMAKE}" --no-designer-plugin --no-qml-plugin "${CONFIGURE_ARGS[@]}"; then
  set +x
  echo "[ERROR] configure.py failed"
  [[ -f config.log ]] && sed -n '1,160p' config.log
  exit 20
fi
set +x

echo "[INFO] Building (jobs=${MAKE_JOBS})"
make -j"${MAKE_JOBS}" || { echo "[ERROR] Build failed"; exit 30; }
echo "[INFO] Installing"
make install || { echo "[ERROR] Install failed"; exit 40; }

popd >/dev/null
popd >/dev/null

echo "[INFO] Running negative import validation"
VALIDATION_SCRIPT="$(mktemp "${BUILD_PARENT}/validate_pyqt_XXXX.py")"
cat > "${VALIDATION_SCRIPT}" <<'PY'
from PyQt5 import QtCore, QtGui, QtWidgets
print("Qt Version:", QtCore.QT_VERSION_STR)
print("PyQt Version:", QtCore.PYQT_VERSION_STR)
disabled = ["QtWebEngineWidgets","QtWebEngineCore","QtWebEngineQuick","QtWebChannel",
            "QtWebSockets","QtPositioning","QtLocation","QtBluetooth","QtNfc",
            "QtSensors","QtSerialPort","QtTest"]
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

ENABLE_MULTIMEDIA="${ENABLE_MULTIMEDIA}" "${python_cmd}" "${VALIDATION_SCRIPT}" || { echo "[ERROR] Validation failed"; exit 50; }

echo "[INFO] Generating manifest"
SITE_PKGS="$(${python_cmd} -c 'import site; print(next(p for p in site.getsitepackages() if \"site-packages\" in p))')"
MANIFEST="${BUILD_PARENT}/pyqt5_manifest_$(date +%Y%m%d%H%M%S).txt"
find "${SITE_PKGS}/PyQt5" -type f -print | LC_ALL=C sort > "${MANIFEST}"
( command -v sha256sum >/dev/null && sha256sum "${MANIFEST}" || shasum -a 256 "${MANIFEST}" ) > "${MANIFEST}.sha256"
SIZE_FILE_COUNT=$(wc -l < "${MANIFEST}")
PKG_SIZE=$(du -sh "${SITE_PKGS}/PyQt5" | awk '{print $1}')
echo "[INFO] Installed file count: ${SIZE_FILE_COUNT}"
echo "[INFO] Installed PyQt5 directory size: ${PKG_SIZE}"
duration=$(( $(date +%s) - start_epoch ))
echo "[INFO] Complete in ${duration}s"
echo "[INFO] Manifest: ${MANIFEST}"
echo "[INFO] Manifest hash: $(cut -d' ' -f1 "${MANIFEST}.sha256")"
echo "[INFO] Done."
exit 0