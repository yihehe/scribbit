# Validation record

## Public-source preparation — November 14, 2026

Version: **0.5.2**, build **8**. Package/executable: Scribbit; core: ScribbitCore.
Bundle identifier: `com.stephenhe.Scribbit`.

This identity starts with fresh preferences. Selected-file bookmarks and login
registration from differently identified development builds are not migrated.
No existing note, production settings, installed/running app or login registration
was modified during preparation.

### Reproduce

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/coverage.sh
bash -n Scripts/*.sh
plutil -lint Resources/Info.plist
codesign --verify --strict build/Scribbit.app
```

With explicit permission to open disposable test windows:

```sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

### Current checks

| Check | Result |
| --- | --- |
| Clean-source export: unit/filesystem tests | **75 tests in 8 suites passed** |
| Clean-source export: signed release build | **Passed**; produced build/Scribbit.app with no ignored source/build inputs |
| Metadata, executable, bundled license and signature | **Passed**; Scribbit identity/version, one Scribbit executable, byte-identical MIT license, strict signature; no retired editor packages or Testing framework linked |
| Native GUI smoke on renamed app | **Passed**, exit 0 / GUI_SMOKE_PASS; all five composition contracts, indentation/history, presenter lifecycle, controls/speed/motion, hover and save/conflict gates |
| Public-file inventory, branding/local-path/secret-pattern screen, links | **53 UTF-8 files screened**, no findings; 16 local Markdown links resolve after the platform-reference cleanup; no public symlinks or files over 1 MiB |
| Script/plist/workflow syntax | **Passed**; bash -n, plutil and YAML parser |
| Coverage command | **Passed**; unit-only line coverage 15.52% overall, including UI/harness code not run by the unit suite; core files 87.01–100% line coverage; separate GUI results are not merged |
| Reference text screen | No matches in five consecutive whitespace-normalized, nonblank/noncomment lines totaling at least 100 characters, against the inspected local reference checkouts; not a legal/provenance determination |
| Reference license review | GPL-3.0-or-later and separate trademark/trade-dress policy checked; no MIT exception identified for the referenced implementation; publication licensing boundary remains unadjudicated |
| Platform-reference cleanup | Public named-reference sweep passed; documentation and one source comment changed, executable code unchanged; full tests were not rerun for this documentation-only follow-up |
| GitHub Actions | Workflow added; not run on GitHub |
| Real notch, physical IME candidate UI, login cycle, notarization, long-running resource use | Manual/not run for this change |

The local environment is Apple silicon, macOS 26.7.3 and Apple Swift 6.3.3.
The CLT manifest-interface workaround is local to ignored build output. Filesystem
tests use actual NSFileCoordinator and require approved host access when a command
sandbox blocks the macOS coordination service.

Two metadata regression tests cover the display/executable names, bundle identity,
accessory mode and minimum macOS version. Core/editor behavior was not rewritten.
Historical experiments, naming research, old logs, downloaded source and retired
dependency notices are not part of the public source tree or current bundle.

Local evidence is intentionally ignored under `build/public-prep/`: clean-tests.log,
clean-build.log, clean-coverage.log, gui.log, audit.json, linked-libraries.txt,
reference-similarity.json and editor-similarity.json. Historical originals are
preserved there rather than rewritten as evidence for the current app. The
clean-source export contains only the files Git would include, without Git
metadata, downloaded source or reused build caches.

### Limits

Source publication is not a notarized app release. Local ad-hoc signing does not
establish Gatekeeper acceptance or login approval on another Mac. Automated GUI
tests use app-local events and API-driven composition, not every keyboard layout,
physical input method or physical-notch interaction.

The repository screen is a bounded text/path/packaging check, not a guarantee that
no secret exists, a vulnerability audit, a trademark clearance or legal clearance.
The [platform reference catalog](REFERENCE.md) documents the Apple APIs used;
it does not establish source independence or resolve licensing obligations.
