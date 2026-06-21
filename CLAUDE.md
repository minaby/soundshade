# SoundShade — project notes for Claude

## Versioning policy (IMPORTANT)

Bump the app version on **every** change that ships (any code/resource change that
gets committed). Do this as part of the same change — don't wait to be asked.

- Version lives in `Sources/SoundShade/Resources/Info.plist`:
  - `CFBundleShortVersionString` — the user-facing version (e.g. `1.01`). Increment this.
  - `CFBundleVersion` — integer build number. Increment by 1 each time.
- Numbering style the user uses: `1.0.0` → `1.01` → `1.02` → ... (two-digit patch).
  Keep following that style unless told otherwise.
- After bumping: rebuild the bundle with `bash build_app.sh`, then ad-hoc sign with
  `codesign --force --deep -s - SoundShade.app`.
- When committing, also create an annotated git tag `vX.YZ` matching the new version
  and push it (`git push origin vX.YZ`).

Current version: see Info.plist (last set to 1.01).

## Build / package

- `bash build_app.sh` builds release and assembles `SoundShade.app` in the repo root.
- The app bundles the `m1ddc` CLI (external-display DDC control) under
  `Contents/Resources/SoundShade_SoundShade.bundle/m1ddc`.

## Architecture notes

- `BrightnessEngine` controls external display brightness via `m1ddc`. Displays are
  addressed by **stable system UUID** (`ConnectedDisplay.m1ddcSpecifier`), NOT by
  positional index — m1ddc's display ordering differs from `NSScreen.screens` and
  drifts after sleep/wake/reconnect.
