# PyQt5 Optimized Build (Jetson Orin) – Progress & Technical Log

## 1. Executive Summary

Goal: Provide a minimal, reproducible PyQt5 5.15.x build on Jetson Orin that excludes heavy / unused Qt modules (notably all WebEngine components) to reduce build time, disk footprint, and runtime memory usage, while preserving core desktop GUI functionality (QtCore, QtGui, QtWidgets).

Current Status: Clean environment prepared (`pyqtbuild`), modern packaging split understood (builder: `sip` / `sipbuild`, runtime: `PyQt5.sip`), namespaced runtime verified. Hardened build script patch (dependency pins, module exclusion, runtime detection) is pending application before running the PyQt5 5.15.10 build.

---

## 2. Scope

### **In-Scope**

- Build PyQt5 5.15.10 against system Qt 5.15.3 (JetPack 6.2.1+b38).
- Exclude non-essential Qt bindings (WebEngine stack, device/network extras).
- Harden build script (version pins, verification, deterministic output).
- Document sip vs PyQt5-sip packaging transition.
- Post-build validation (negative import tests).

### **Out of Scope (Current Phase)**

- Qt 6 migration.
- Cross-compilation for non-Orin devices.
- Wheel redistribution / packaging automation.
- Performance benchmarking & GPU GUI profiling.

---

## 3. Target Versions / Components

| Component            | Target / Constraint                 | Notes                                              |
|----------------------|--------------------------------------|----------------------------------------------------|
| System Qt            | 5.15.3 (JetPack-provided)            | Avoid mixing Qt major/minor outside 5.15 series    |
| PyQt5                | 5.15.10                              | Stable; ABI-compatible with system Qt              |
| sip (builder)        | >=6.7,<6.12 (installed: 6.11.1)      | <6.12 avoids configure regression                  |
| PyQt5-sip (runtime)  | >=12.11,<13 (installed: 12.17.0)     | Provides `PyQt5.sip` extension module              |
| Python               | 3.10 (`pyqtbuild` env)               | Clean environment after prior corruption           |

---

## 4. Optimization Goals

1. Exclude large, unused Qt subsystems (especially WebEngine/Chromium stack).
2. Lower peak RAM usage (MAKE_JOBS=1 + enlarged swap).
3. Eliminate nondeterminism (explicit pins + sanitized indexes).
4. Provide clear failure signals (strict early dependency validation).
5. Make rebuilds trivial & reproducible on fresh Jetson flash.

### **Success Criteria**

- PyQt5 5.15.10 imports cleanly.
- Disabled modules raise `ImportError`.
- Peak build memory stays within device RAM + configured swap margin.
- Build script exit codes reflect failure points.
- Repeat build produces identical module set (hashable file list optional).

---

## 5. Excluded Qt Modules (Planned)

```text
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
(Optional) QtMultimedia
```

**Rationale:** These introduce large dependency surfaces (Chromium integration, device stacks, networking extras) irrelevant for minimal desktop/control UIs. Omit unless explicitly required.

---

## 6. Build Strategy

- Fetch source tarball for PyQt5 5.15.10.
- Install pinned: `sip>=6.7,<6.12` and `PyQt5-sip>=12.11,<13`.
- Use `python -m pip` always; set `PYTHONNOUSERSITE=1`.
- Provide environment variable controls: `MAKE_JOBS`, `ENABLE_MULTIMEDIA`, `SKIP_APT`.
- Single-thread default: `MAKE_JOBS=1` (raise only after first successful build).
- Expand swap (script: `increase_to_60gb_swap.sh`).
- Post-build: verify required modules, assert excluded imports fail.

---

## 7. Timeline of Key Events

| # | Event / Decision | Outcome |
|---|------------------|---------|
| 1 | Initial PyQt5 build attempt | Legacy flags; missing compiled modules |
| 2 | Investigated build failure | Flag `--sip-module` identified as obsolete |
| 3 | sip 6.12.x regression | Pin established: `<6.12` |
| 4 | Env corruption (stdlib anomalies) | Abandoned old env |
| 5 | Created clean `pyqtbuild` env | Fresh baseline |
| 6 | Installed only `sip` → runtime missing | Recognized packaging split |
| 7 | Added `PyQt5-sip` | Namespaced `PyQt5.sip` available |
| 8 | Verified namespaced spec | Build unblocked conceptually |
| 9 | Drafted script hardening plan | Pending implementation |

---

## 8. Issues & Root Causes

| Issue | Root Cause | Resolution Status |
|-------|------------|------------------|
| Configure TypeError | sip >=6.12 behavior regression | Pin `<6.12` (Done) |
| `ModuleNotFoundError: sip` | Runtime moved to `PyQt5.sip` namespace | Updated detection (Planned in script) |
| Network retry noise | Dead pip extra index (`jetson-ai-lab`) | Removed (Done) |
| Corrupted stdlib imports | Damaged earlier env | Recreated env (Done) |
| Obsolete `--sip-module` usage | Legacy instruction mismatch | Remove in patch (Pending) |
| One-path runtime check | Only tested `sip` top-level | Dual-spec logic needed (Pending) |

---

## 9. Current State Snapshot

| Aspect                     | State / Value                            |
|----------------------------|-------------------------------------------|
| Python env                 | `pyqtbuild` (clean)                      |
| sip build system (`sipbuild`) | Present                               |
| Runtime sip                | `PyQt5.sip` extension present            |
| Top-level `sip` module     | Absent (expected)                        |
| Script hardening applied   | Not yet                                   |
| PyQt5 build executed       | Not yet                                   |
| README updated             | Not yet                                   |

---

## 10. Pending Action Items

| Priority | Action | Status | Notes |
|----------|--------|--------|-------|
| High | Patch `build_pyqt5_jetson.sh` (pins, detection, exclusions) | Pending | Remove `--sip-module` |
| High | Execute PyQt5 5.15.10 build | Pending | Capture `build_pyqt5.log` |
| High | Run negative import validation | Pending | Gate success criteria |
| Medium | Add README optimization & sip packaging section | Pending | Link to this doc |
| Medium | Optional `sip` shim creation (legacy code) | Optional | Only if third-party expects `import sip` |
| Low | Remove dead URLs in other scripts | Pending | e.g. obsolete wheel sources |
| Low | Add test harness script (`scripts/utils/test_pyqt5_minimal.py`) | Pending | Simple GUI sanity |
| Low | Record disk & memory metrics | Pending | After first build |

---

## 11. Post-Build Validation Script

```bash
python - <<'PY'
from PyQt5 import QtCore, QtWidgets
print("Qt Version:", QtCore.QT_VERSION_STR)
print("PyQt Version:", QtCore.PYQT_VERSION_STR)
disabled = [
    "QtWebEngineWidgets","QtWebEngineCore","QtWebEngineQuick","QtWebChannel",
    "QtWebSockets","QtPositioning","QtLocation","QtBluetooth","QtNfc",
    "QtSensors","QtSerialPort","QtTest"
]
ok = []
warn = []
for m in disabled:
    try:
        __import__("PyQt5."+m)
        warn.append(m)
    except ImportError:
        ok.append(m)
print("Excluded OK:", ok)
if warn:
    print("WARNING: These modules unexpectedly present:", warn)
    raise SystemExit(1)
print("All exclusions enforced.")
PY
```

---

## 12. Core Commands (Quick Reference)

### **Environment Prep**

```bash
conda create -n pyqtbuild python=3.10 -y
conda activate pyqtbuild
python -m pip install --upgrade pip
python -m pip install --no-cache-dir "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"
```

### **Verify Runtime Presence**

```bash
python -c "import importlib.util;print(importlib.util.find_spec('PyQt5.sip'))"
```

### **Run Build (after script patch)**

```bash
PYQT_VERSION=5.15.10 ENABLE_MULTIMEDIA=0 MAKE_JOBS=1 SKIP_APT=1 \
  ./scripts/utils/build_pyqt5_jetson.sh |& tee build_pyqt5.log
```

### **Optional Shim (only if needed)**

```bash
python - <<'PY'
import importlib.util, sys, os
if importlib.util.find_spec('sip') is None and importlib.util.find_spec('PyQt5.sip'):
    site = [p for p in sys.path if p.endswith('site-packages')][0]
    shim = os.path.join(site, 'sip.py')
    if not os.path.exists(shim):
        with open(shim,'w') as f: f.write('from PyQt5.sip import *  # legacy shim\n')
        print("Shim created:", shim)
    else:
        print("Shim already exists:", shim)
else:
    print("Shim not required.")
PY
```

---

## 13. Script Hardening Checklist

- [ ] Version pins: `sip>=6.7,<6.12`, `PyQt5-sip>=12.11,<13`
- [ ] Sanitize pip indices (no dead extras)
- [ ] Always use `python -m pip`
- [ ] Export `PYTHONNOUSERSITE=1`
- [ ] Remove legacy `--sip-module`
- [ ] Dual runtime detection (`sip` OR `PyQt5.sip`)
- [ ] Pre-flight abort if builder/runtime missing
- [ ] Temp build dir + trap cleanup
- [ ] Explicit configure args echo
- [ ] `MAKE_JOBS` default 1
- [ ] Negative import tests post-install
- [ ] Optional shim (only if demanded)
- [ ] Structured exit codes

---

## 14. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| New sip regression | Build failure | Medium | Maintain pin; retest periodically |
| Missing Qt dev headers | Configure abort | Low | Ensure `qtbase5-dev` via APT step |
| OOM during compile | Build abort, wasted time | Medium | Large swap + serial make first |
| Packaging layout change (`PyQt5.sip`) | Detection break | Low | Generic spec-finder logic |
| Local path shadowing `sip` | False negatives | Low | Pre-flight path scan |
| Silent partial install | Runtime mismatch | Low | Post-build verification block |

---

## 15. Changelog (Internal)

| Date Tag | Change |
|----------|--------|
| Early | Initial attempt (legacy flags) |
| +1 | Defined exclusion list |
| +2 | Found sip >=6.12 regression, pinned |
| +3 | Rebuilt clean env |
| +4 | Understood packaging split |
| +5 | Namespaced runtime verified |
| Pending | Apply hardened script & build |

---

## 16. Disabled Modules Rationale

- **WebEngine***: Chromium embedding; biggest weight; high RAM/runtime overhead.
- **Positioning/Location/Sensors/Bluetooth/NFC**: Not needed for standard control UI.
- **SerialPort**: Optional; include only for hardware integration projects.
- **Test**: Unit-test binding layer unnecessary in deployed runtime.

---

## 17. Identifying sip Components

```bash
python - <<'PY'
import importlib.util
for name in ['sipbuild','sip','PyQt5.sip']:
    print(name, '->', importlib.util.find_spec(name))
PY
```

Interpretation:

- `sipbuild`: must exist.
- `PyQt5.sip`: expected runtime extension.
- `sip`: may be None (normal).

---

## 18. SIP Version Notes

Builder sip version (e.g. 6.11.1) may differ from embedded runtime API version (e.g. 6.10.0) compiled into `PyQt5.sip`. Acceptable if within compatibility window enforced by pins.

---

## 19. Glossary

| Term | Definition |
|------|------------|
| sip | Historic runtime module (now usually absent) |
| sipbuild | Build system Python package from `sip` distribution |
| PyQt5-sip | Distribution providing runtime `PyQt5.sip` extension |
| Namespaced sip | Import path: `from PyQt5 import sip` |
| MAKE_JOBS | Parallel build threads setting |
| Negative import test | Confirm exclusion by expecting ImportError |

---

## 20. Next Milestone

Apply hardened script → Run build → Capture `build_pyqt5.log` → Execute validation script → Record results in Section 21.

---

## 21. Build Validation (Template – Fill After First Success)

```text
Build Date: YYYY-MM-DD
PyQt5 Version: (expect 5.15.10)
Qt Version: (expect 5.15.3 or system equivalent)
Excluded Modules Confirmed: [...list...]
Wheel / Install Path: ...
Build Duration: ...
Peak Memory (optional): ...
Notes: ...
```

---

## 22. Contribution Workflow

1. Open Issue describing desired module changes / additional exclusions.
2. Provide build log + validation script output.
3. Submit PR with diff (script + doc) and rationale.
4. Reviewer confirms reproducibility on clean Jetson.

---

## 23. Future Enhancements (Backlog)

- Generate a minimal wheel artifact.
- Add CI container recipe for deterministic rebuild.
- Add hash manifest of installed PyQt5 files.
- Optional QtMultimedia toggle auto-detection.
- Metrics collection script for footprint delta vs stock PyQt5.

---

_This document will evolve as the build script lands and validation data is gathered._
