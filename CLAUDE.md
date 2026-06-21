# SoundShade — project notes for Claude

## Versioning policy (IMPORTANT)

Version bumping is **automated** by a git pre-commit hook (`.githooks/pre-commit`).
Any commit that touches shipping files (`Sources/`, `Resources/`, `*.swift`,
`Package.swift`, `build_app.sh`) auto-increments the version. Doc/meta-only commits
(`*.md`, `.githooks/`, LICENSE, etc.) are skipped.

One-time setup after cloning (the hook path is a local git setting, not committed):

```
git config core.hooksPath .githooks
```

To bypass for a specific commit (e.g. a release or merge commit):
`SKIP_VERSION_BUMP=1 git commit ...`

If editing the version manually instead, the rule is: bump it on every shipping change.

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

- `bash build_app.sh` builds release and assembles the bundle in `dist.noindex/`.
  The `.noindex` suffix keeps Spotlight/LaunchServices from auto-registering this
  dev build. Do NOT output the bundle to the repo root: a registered `.app` copy on
  the external volume makes macOS prompt for "removable volume" access and can make
  the login item / audio-driver helper resolve `com.soundshade.app` to the wrong copy.
  Always run/install from `/Applications`. If a stray copy ever gets registered, remove
  it with `lsregister -u <path/to/SoundShade.app>`.
- The app bundles the `m1ddc` CLI (external-display DDC control) under
  `Contents/Resources/SoundShade_SoundShade.bundle/m1ddc`.

## Architecture notes

- `BrightnessEngine` controls external display brightness via `m1ddc`. Displays are
  addressed by **stable system UUID** (`ConnectedDisplay.m1ddcSpecifier`), NOT by
  positional index — m1ddc's display ordering differs from `NSScreen.screens` and
  drifts after sleep/wake/reconnect.
