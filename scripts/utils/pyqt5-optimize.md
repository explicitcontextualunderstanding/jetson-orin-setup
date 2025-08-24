# PyQt5 Optimized Build (Jetson Orin) – Hibernate Snapshot (Paused Work)

_Last updated: 2025-08-24_

This document freezes the current state of the minimal PyQt5 5.15.10 build effort so we can suspend work and later resume with full context.

---

## 0. Quick Resume Cheat Sheet

If you only read one section when coming back, read this.

1. Activate env (or recreate):
   ```bash
   conda activate pyqtbuild || { conda create -n pyqtbuild python=3.10 -y && conda activate pyqtbuild; }
   python -m pip install --upgrade pip
   python -m pip install --no-cache-dir "sip>=6.7,<6.12" "PyQt5-sip>=12.11,<13"
   ```
2. Ensure build script includes configure patch (Section 6.3). If not, add it.
3. Run build:
   ```bash
   PYQT_VERSION=5.15.10 MAKE_JOBS=1 ENABLE_MULTIMEDIA=0 SKIP_APT=1 \
     ./scripts/utils/build_pyqt5_jetson.sh |& tee build_pyqt5.log
   ```
4. If `TypeError: '<' not supported between int and NoneType` appears again inside `configure.py:check_sip()`, confirm patch inserted before `configure.py` runs.
5. After success, run validation script (Section 11) and fill Section 21 template.

---

## 1. Executive Summary

Goal: Produce a minimal, reproducible PyQt5 5.15.10 build on Jetson Orin (system Qt 5.15.3) excluding heavy subsystems (especially WebEngine) while preserving `QtCore`, `QtGui`, `QtWidgets`.  
Status: Build still blocked at `configure.py` `check_sip()` due to internal version tuple logic causing `TypeError` despite correct `sip -V` output (`6.11.1`). Pending mitigation: patch `configure.py` (or inject pre-execution monkey patch) to override broken SIP version detection via a forced environment variable.

---

## 2. Scope (Unchanged)

In-Scope:
- Minimal PyQt5 5.15.10 build.
- Module exclusions & negative import validation.
- Hardened reproducibility (pins, deterministic output).

Out-of-Scope (current pause):
- Qt 6 migration.
- Distribution automation (wheel publication).
- Performance profiling.

---

## 3. Target Versions / Constraints

| Component            | Target / Pin                 | Notes |
|---------------------|------------------------------|-------|
| System Qt           | 5.15.3 (JetPack)             | ABI baseline |
| PyQt5               | 5.15.10                      | Selected modern 5.15.x |
| sip (builder)       | >=6.7,<6.12 (using 6.11.1)   | Avoid >=6.12 regression |
| PyQt5-sip (runtime) | >=12.11,<13 (using 12.17.0)  | Provides `PyQt5.sip` |
| Python              | 3.10                         | Conda env `pyqtbuild` |

---

## 4. Optimization Goals (Recap)

1. Strip unused bindings (WebEngine etc.).
2. Constrain RAM usage (serial build first).
3. Deterministic rebuild (pins + manifest).
4. Fail fast with clear diagnostics.
5. Negative import validation for exclusions.

Success Criteria (still pending completion for 5.15.10):
- Core modules import.
- Invalid (excluded) modules raise `ImportError`.
- Manifest reproducibility (optional hash list).
- Clean exit codes & documented metrics.

---

## 5. Planned Excluded Qt Modules

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

Rationale: Remove Chromium stack + device/IO subsystems not needed for basic desktop / control UI usage.

---

## 6. Current Blocker & Planned Mitigation

### 6.1 Symptom

`configure.py` crashes with:
```
TypeError: '<' not supported between instances of 'int' and 'NoneType'
```
inside `check_sip()` comparing parsed SIP version tuples.

### 6.2 Confirmed Facts

- `sip -V` (wrapper) outputs: `6.11.1\n`.
- Hexdump validates no hidden characters.
- Environment uses separate builder/runtime distributions (`sip`, `PyQt5-sip`).
- Failure occurs before build steps, so no compiled bindings yet.

### 6.3 Mitigation Plan (Patch Injection)

Insert a patch segment right after extracting PyQt5 source and before invoking `python configure.py`:

Pseudo-diff to add in `build_pyqt5_jetson.sh`:

```bash
PATCH_FILE="$SRC_DIR/configure.py"
if [[ -f "$PATCH_FILE" && -z "${PYQT_CONFIG_PATCHED:-}" ]]; then
  echo "[INFO] Patching configure.py to force SIP version if PYQT_FORCE_SIP_VERSION is set"
  python - <<'PY'
import os, re, sys
path = os.environ.get("PATCH_FILE")
force = os.environ.get("PYQT_FORCE_SIP_VERSION")
if not path or not os.path.exists(path) or not force:
    sys.exit(0)
txt = open(path,'r',encoding='utf-8').read()
# Inject a guard near the start of check_sip definition.
pat = r"def check_sip\\(.*?\\):"
if re.search(pat, txt):
    def repl(m):
        return m.group(0) + f"""
    # BEGIN injected patch
    _forced = os.environ.get('PYQT_FORCE_SIP_VERSION')
    if _forced:
        class _F: pass
        class _V(tuple):
            def __lt__(self, other): return tuple(self) < tuple(other)
        parts=[int(p) for p in _forced.split('.')[:3]]
        while len(parts)<3: parts.append(0)
        return _V(tuple(parts)), True
    # END injected patch
"""
    new = re.sub(pat, repl, txt, count=1, flags=re.DOTALL)
    if new != txt:
        open(path,'w',encoding='utf-8').write(new)
        print("Patch applied to configure.py")
PY
  export PYQT_CONFIG_PATCHED=1
fi
```

Then run configure with:
```bash
PYQT_FORCE_SIP_VERSION=6.11.1 python configure.py ...
```

On success, the forced version short-circuits problematic parsing.

### 6.4 Alternate (If Patch Rejected)

- Downgrade to a PyQt5 release whose `configure.py` lacks problematic logic (e.g. earlier 5.15.x) — risk of missing security fixes.
- Use legacy stack (PyQt5 5.10.1 + sip 4.19.8) — working, but deviates from target and loses modern API compatibility.
- Build from PyQt5 git + cherry-pick fixed upstream commit (if later commit addresses this) — requires investigation.

### 6.5 Follow-Up After Resume

Once build succeeds with patch:
1. Capture diff of modified `configure.py`.
2. Open upstream issue referencing failure scenario (Jetson + sip 6.11.1).
3. Gate future rebuilds: allow disabling patch via env flag.

---

## 7. Timeline (Condensed)

| # | Event | Result |
|---|-------|--------|
| 1 | Initial attempt with obsolete flags | Configure failures |
| 2 | Identified `--sip-module` obsolete | Removed in concept |
| 3 | sip >=6.12 regression seen | Pin `<6.12` |
| 4 | Clean environment created | Fresh baseline |
| 5 | Realized sip packaging split | Added `PyQt5-sip` |
| 6 | Wrap `sip -V` to normalize | Output stable (6.11.1) |
| 7 | Configure still crashes | Root cause unresolved |
| 8 | Patch strategy defined | Not yet applied |
| 9 | Work paused | Snapshot taken |

---

## 8. Issues Matrix (Updated)

| Issue | Root Cause | Status | Next Action |
|-------|------------|--------|------------|
| `TypeError` in `check_sip` | Version tuple parsing defect | Open | Apply patch Section 6.3 |
| Missing runtime `sip` | Packaging split | Resolved | None |
| Obsolete flag usage | Legacy docs | Resolved (concept) | Ensure script updated |
| Environment corruption | Prior accidental modifications | Resolved | None |
| Unvalidated exclusions | Build blocked pre-install | Pending | Run post-build script |
| No manifest generated | Build not complete | Pending | Implement after success |

---

## 9. Environment Snapshot

| Aspect | State |
|--------|-------|
| Conda env | `pyqtbuild` |
| Python | 3.10 |
| sip builder | 6.11.1 |
| PyQt5-sip runtime | 12.17.0 |
| PyQt5 build | Not completed |
| Patch applied? | No (pending) |
| Logs | Last failed configure run (not archived) |

---

## 10. Pending Work Items (Frozen List)

| Priority | Task | Owner (future) | Notes |
|----------|------|----------------|-------|
| High | Implement `configure.py` patch | Resume engineer | Section 6.3 |
| High | Re-run build & capture `build_pyqt5.log` | Resume engineer | Store under `logs/` (create) |
| High | Run negative import validation | Resume engineer | Section 11 |
| Medium | Generate manifest (file list + hashes) | Resume engineer | Scripts addition |
| Medium | Document metrics (RAM/time) | Resume engineer | Fill Section 21 |
| Medium | Upstream issue creation | Resume engineer | Include patch diff |
| Low | Optional legacy `sip` shim | Only if external deps need `import sip` | Avoid by default |
| Low | README update referencing optimization doc | Docs | Link from project root |

---

## 11. Post-Build Validation Script (Reference)

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
ok=[]; unexpected=[]
for m in disabled:
    try:
        __import__("PyQt5."+m)
        unexpected.append(m)
    except ImportError:
        ok.append(m)
print("Excluded OK:", ok)
if unexpected:
    print("UNEXPECTED modules present:", unexpected)
    raise SystemExit(1)
print("All exclusions enforced.")
PY
```

---

## 12. Manifests (Planned Structure)

Upon success:
```bash
python - <<'PY'
import hashlib, os, json, time
base = next(p for p in __import__('sys').path if p.endswith('site-packages'))
pyqt = os.path.join(base,'PyQt5')
entries=[]
for root,_,files in os.walk(pyqt):
    for f in files:
        path=os.path.join(root,f)
        with open(path,'rb') as fh:
            h=hashlib.sha256(fh.read()).hexdigest()[:16]
        entries.append({"rel":os.path.relpath(path, pyqt),"sha256_16":h,"size":os.path.getsize(path)})
print(json.dumps({"timestamp":time.time(),"count":len(entries),"files":entries},indent=2))
PY > pyqt5_manifest.json
```
Store at `artifacts/pyqt5_manifest.json` for reproducibility.

---

## 13. Risk Snapshot (At Pause)

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Upstream changes alter patch point | Low | Medium | Pin PyQt5 sdist hash |
| Repro patch forgotten on resume | Medium | High | This doc; Section 0 |
| Hidden dependency missed | Low | Medium | Post-build import audit |
| OOM on first compile | Medium | Medium | Serial `MAKE_JOBS=1`; swap script |

---

## 14. Parking Lot (Future Enhancements)

- CI container recipe for automated rebuild.
- Add optional `--list-disabled` CLI to script.
- Auto-detect presence of large modules and warn if not excluded.
- Add GPU resource usage sampler during build (profiling).
- Switch to wheel production stage for distribution (PEP 517).

---

## 15. Minimal Script Requirements (Integrity Checklist)

Ensure `build_pyqt5_jetson.sh` has:
- Environment pins (`sip>=6.7,<6.12`, `PyQt5-sip>=12.11,<13`).
- Dual runtime detection (`sip` or `PyQt5.sip`).
- Removal of obsolete `--sip-module`.
- Patch injection block (Section 6.3).
- Module exclusion flags.
- Negative import validation stage.
- Optional manifest generation (future).
- Clear logging prefixes `[INFO]`, `[ERROR]`, `[DEBUG]`.

---

## 16. Upstream Reporting Template (Draft)

When opening an issue upstream:

Title: PyQt5 5.15.10 configure.py check_sip() TypeError with valid sip 6.11.1 on ARM (Jetson)

Body Outline:
- Environment (Python 3.10, sip 6.11.1, PyQt5-sip 12.17.0).
- Command line used for `python configure.py`.
- Exact traceback.
- Output of `repr(open('configure.py').read()[start:end])` around `check_sip`.
- Confirmation that `sip -V` returns plain `6.11.1`.
- Patch diff (forced version guard) as workaround.

---

## 17. Glossary (Abbrev Recap)

| Term | Meaning |
|------|---------|
| Negative Import Test | Attempting to import excluded modules expecting failure |
| Forced SIP Version | Injected override of `check_sip()` logic |
| Manifest | Hash + size listing of installed PyQt5 files |

---

## 18. Hibernation Integrity Checks (Run Before Leaving — Optional)

```bash
conda env list | grep pyqtbuild || echo "Env missing!"
python -c "import sys; print(sys.version)" 2>/dev/null
python - <<'PY'
import importlib.util as u
print("sipbuild:", u.find_spec("sipbuild") is not None)
print("PyQt5.sip:", u.find_spec("PyQt5.sip") is not None)
print("sip (legacy):", u.find_spec("sip") is not None)
PY
```

---

## 19. Known Good Legacy Fallback

A working (but older) path exists: `scripts/utils/build_pyqt5_ARM64_jetson_conda.sh` builds PyQt5 5.10.1 with sip 4.19.8. Use only if modern path blocks critical progress; lacks newer API compatibility.

---

## 20. Resume Checklist (Tick When Returning)

- [ ] Env `pyqtbuild` present (or recreated).
- [ ] sip + PyQt5-sip versions confirm within pins.
- [ ] PyQt5 5.15.10 sdist downloaded (verify hash optionally).
- [ ] Patch inserted (log line: "Patch applied to configure.py").
- [ ] Build succeeds (no `TypeError`).
- [ ] Validation script passes (all excluded modules absent).
- [ ] Manifest generated & stored.
- [ ] Section 21 completed.

---

## 21. Build Validation (To Be Filled Post-Success)

```text
Build Date: (pending)
PyQt5 Version: (expect 5.15.10)
Qt Version: (expect 5.15.3)
Excluded Modules Confirmed: [...]
Build Duration: ...
Peak Memory (approx): ...
Manifest File: artifacts/pyqt5_manifest.json
Patch Applied: yes/no
Notes: ...
```

---

## 22. Exit Note

Work intentionally paused prior to first successful 5.15.10 build due to unresolved `configure.py` version parsing issue. The next critical action is implementing the forced SIP version patch; all downstream steps depend on that unblock.
