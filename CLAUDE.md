# SoundShade — project notes for Claude

## Versioning policy (IMPORTANT)

Version stamping is **automated in two places**, both writing the same
`YYMMDD.HHmm` value at the time they run:
- `build_app.sh` stamps it on every build (so the version always reflects the
  actual build you're running, even without committing).
- The git pre-commit hook (`.githooks/pre-commit`) also stamps it on any commit
  that touches shipping files (`Sources/`, `Resources/`, `*.swift`,
  `Package.swift`, `build_app.sh`), as a safety net for commits made without
  running `build_app.sh` first. Doc/meta-only commits (`*.md`, `.githooks/`,
  LICENSE, etc.) are skipped.

One-time setup after cloning (the hook path is a local git setting, not committed):

```
git config core.hooksPath .githooks
```

To bypass for a specific commit (e.g. a release or merge commit):
`SKIP_VERSION_BUMP=1 git commit ...`

If editing the version manually instead, the rule is: bump it on every shipping change.

- Version lives in `Sources/SoundShade/Resources/Info.plist`:
  - `CFBundleShortVersionString` and `CFBundleVersion` — both set to the same value.
- Format: `YYMMDD.HHmm`, stamped at build/commit time, **24h clock**. e.g. a commit
  made June 28 2026 at 14:05 → `260628.1405`. Just write out whatever the actual
  build time is — there is no separate incrementing counter anymore.
- After bumping: rebuild the bundle with `bash build_app.sh`, then ad-hoc sign with
  `codesign --force --deep -s - SoundShade.app`.
- When committing, also create an annotated git tag `vYYMMDD.HHmm` matching the new
  version and push it (`git push origin vYYMMDD.HHmm`).

Current version: see Info.plist.

## Build / package

- `bash build_app.sh` builds release and assembles the bundle in `dist.noindex/`.
  The `.noindex` suffix keeps Spotlight/LaunchServices from auto-registering this
  dev build. Do NOT output the bundle to the repo root: a registered `.app` copy on
  the external volume makes macOS prompt for "removable volume" access and can make
  the login item / audio-driver helper resolve `com.soundshade.app` to the wrong copy.
  Always run/install from `/Applications`. If a stray copy ever gets registered, remove
  it with `lsregister -u <path/to/SoundShade.app>`.
- Xcode lives on the external volume (`/Volumes/Ext-Storage/Apps/Xcode.app`), so SwiftPM
  bakes an `LC_RPATH` to its Swift toolchain into the binary. dyld probing that path at
  launch triggers "removable volume" prompts. `build_app.sh` strips any non-system rpath
  after copying the executable (keeps `/usr/lib/swift` and `@loader_path`). If you ever
  build by other means, run `otool -l <binary> | grep -A2 LC_RPATH` and delete external
  ones with `install_name_tool -delete_rpath <path> <binary>`.
- The app bundles the `m1ddc` CLI (external-display DDC control) under
  `Contents/Resources/SoundShade_SoundShade.bundle/m1ddc`.

## Architecture notes

- `BrightnessEngine` controls external display brightness via `m1ddc`. Displays are
  addressed by **stable system UUID** (`ConnectedDisplay.m1ddcSpecifier`), NOT by
  positional index — m1ddc's display ordering differs from `NSScreen.screens` and
  drifts after sleep/wake/reconnect.
