# Thunderbird Windows Build Notes

## Summary

This document records the Windows 11 Thunderbird build that completed successfully on 2026-05-10 so the same environment can be reused with less trial and error next time.

The key result is that this repository is only the Thunderbird `comm` checkout. A successful build did not happen from this directory alone. The working build used a sibling Gecko source root at `C:\AI\thunderbird\mozilla-unified`, mounted this repository into that root as `comm`, aligned Gecko to a compatible Mercurial changeset, regenerated the Rust vendor tree, and then built and packaged Thunderbird from the Gecko root.

The final successful outputs were:

- `C:\AI\thunderbird\mozilla-unified\obj-thunderbird\dist\bin\thunderbird.exe`
- `C:\AI\thunderbird\mozilla-unified\obj-thunderbird\dist\thunderbird-150.0a1.en-US.win64.zip`

The built application metadata was:

- `Name=Thunderbird`
- `Version=150.0a1`

## Technical Details

### Repositories and revisions

- Thunderbird `comm` checkout path: `C:\AI\thunderbird\thunderbird-desktop`
- Thunderbird branch: `main`
- Thunderbird commit: `762ee446617ca2b80655476bf1c6e56d4c0faa9d`
- Thunderbird commit date: `2026-02-25 10:58:40 +0000`
- Gecko root path: `C:\AI\thunderbird\mozilla-unified`
- Gecko repository type: Mercurial
- Working Gecko changeset: `f2f75ecf8eb443871319273e7e39fb7f01b2581e`
- Gecko branch: `default`
- Gecko changeset date: `2026-02-25 10:49 +0000`
- `comm` inside `mozilla-unified` was a Windows junction pointing to `C:\AI\thunderbird\thunderbird-desktop`

### Working build configuration

File: `C:\AI\thunderbird\mozilla-unified\mozconfig`

```sh
ac_add_options --enable-project=comm/mail
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird
```

This did two important things:

- forced `mach` to build Thunderbird instead of Firefox
- isolated Thunderbird artifacts into `obj-thunderbird` so stale Firefox artifacts did not leak into the build

### Tooling and environment

- OS: Windows 11
- MozillaBuild install path: `C:\mozilla-build`
- Visual Studio with native desktop tooling was present on the machine
- Build commands needed to run inside MozillaBuild, not plain PowerShell

Important note: in a normal PowerShell session, `hg`, `cl.exe`, and `MOZILLABUILD` may appear to be missing. That was expected outside the MozillaBuild environment.

## Working Build Procedure

### 1. Start from the Gecko root, not from this repository root

This repository does not contain a top-level `mach` file, so do not try to build directly from `C:\AI\thunderbird\thunderbird-desktop`.

Use MozillaBuild and point it at the Gecko root:

```powershell
$env:USE_MINTTY='0'
& 'C:\mozilla-build\start-shell.bat' -where 'C:\AI\thunderbird\mozilla-unified'
```

### 2. If bootstrap is needed, use the space-free application alias

This form worked:

```sh
./mach --no-interactive bootstrap --application-choice browser
```

This form failed when passed through `start-shell.bat` from PowerShell because of quoting:

```sh
./mach --no-interactive bootstrap --application-choice "Firefox for Desktop"
```

### 3. Ensure the `comm` mount and root `mozconfig` are correct

The working layout was:

- `C:\AI\thunderbird\mozilla-unified`
- `C:\AI\thunderbird\mozilla-unified\comm` -> junction to `C:\AI\thunderbird\thunderbird-desktop`

The root `mozconfig` must exist in `mozilla-unified`, not only in `comm`.

### 4. Align Gecko to the compatible revision

The Thunderbird GitHub `main` snapshot used here did not build against a much newer Gecko tip from 2026-05. The working fix was to move Gecko back to the February 2026 changeset that matched the Thunderbird snapshot closely enough:

```sh
hg update -C f2f75ecf8eb443871319273e7e39fb7f01b2581e
```

### 5. Resync the Rust vendor tree

After aligning Gecko, regenerate Thunderbird's Rust vendor tree:

```sh
./mach tb-rust vendor
```

### 6. Do a clean Thunderbird build

```sh
./mach clobber
./mach build
```

### 7. Produce the distributable ZIP package

```sh
./mach package
```

## Issues We Met And How They Were Solved

### 1. Tried to build from `thunderbird-desktop` directly

Symptoms:

- no top-level `mach`
- no root `mozconfig`
- build commands from this repo root were invalid

Solution:

- use a Gecko root at `C:\AI\thunderbird\mozilla-unified`
- mount this repository into that root as `comm`
- run all `mach` commands from the Gecko root

### 2. MozillaBuild tools looked missing in plain PowerShell

Symptoms:

- `hg` missing
- `cl.exe` missing
- `MOZILLABUILD` unset

Solution:

- run build commands through `C:\mozilla-build\start-shell.bat`
- do not treat missing `hg` or `cl.exe` in plain PowerShell as a broken setup by itself

### 3. `start-shell.bat` command with `"Firefox for Desktop"` failed

Symptoms:

- `The syntax of the command is incorrect.`

Cause:

- nested quoting through `cmd.exe` and MSYS broke the command line

Solution:

- use `--application-choice browser` instead of the space-containing name

### 4. Wrong product built as Firefox instead of Thunderbird

Symptoms:

- stale object-directory data pointed to Firefox
- old build outputs reported `firefox`

Solution:

- create the root `mozconfig` in `mozilla-unified`
- set `ac_add_options --enable-project=comm/mail`
- use a dedicated object directory with `mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird`

### 5. Old object-directory contamination made cleanup difficult

Symptoms:

- stale files and locked artifacts in an earlier Firefox object directory

Solution:

- stop trying to reuse the old object directory
- build in a fresh dedicated Thunderbird object directory: `obj-thunderbird`

### 6. Cargo frozen or offline dependency failures

Symptoms:

- missing Rust dependencies during build

Solution used during recovery:

```sh
cargo fetch --locked --manifest-path Cargo.toml
```

This prefetched dependencies and helped unblock earlier Cargo failures before the Rust vendor tree was synchronized.

### 7. Rust vendor tree was out of sync

Symptoms:

- build requested `mach tb-rust vendor`
- Rust crates under `comm/third_party/rust` did not match the current lock state

Solution:

```sh
./mach tb-rust vendor
```

### 8. Gecko tip was too new for this Thunderbird snapshot

Symptoms:

- multiple compile failures across Thunderbird code at once
- examples included API mismatches around `WordBreaker`, `EncodingDetector`, `Collator`, `NodeList`, and `nsIFilePicker`

Cause:

- `comm` Git snapshot from 2026-02-25 was being built against Gecko tip from 2026-05-09

Solution:

- roll Gecko back to `f2f75ecf8eb443871319273e7e39fb7f01b2581e`
- rerun `./mach tb-rust vendor`
- run `./mach clobber` and `./mach build` again

This was the turning point that produced the first successful full build.

### 9. `./mach installer` did not produce the desired Windows installer

Symptoms:

- command mapped to an unsupported `make install` path on this platform

Solution:

- use `./mach package` for the successful distributable ZIP output

### 10. `./mach build installers-en-US` failed

Symptoms:

- localized installer packaging failed in artifact code
- the process expected an Hg repository in `comm`

Cause:

- this workspace uses a Git `comm` checkout from GitHub, not an Hg `comm-central` checkout

Solution:

- accept the successful ZIP package as the working distribution artifact for this setup
- if a full localized Windows installer is required later, switch to an Hg-based `comm` checkout or adjust the release packaging flow accordingly

## What We Learned

- The most important decision is choosing the correct build root. `comm` alone is not enough.
- A correct root `mozconfig` and a clean Thunderbird-only object directory prevent a large amount of confusion.
- For this machine, Mercurial-based Gecko setup was more reliable than earlier Git bootstrap attempts.
- Using MozillaBuild consistently matters. Plain PowerShell is useful for inspection, but not as the primary build environment.
- When many Thunderbird source files fail at once on changed Gecko APIs, suspect a revision mismatch before patching Thunderbird source by hand.
- After changing Gecko revision, rerun the Rust vendor step before rebuilding.
- Do not reuse a shell that is currently doing a long bootstrap or build for unrelated checks.
- `./mach package` is enough to get a usable local Windows build artifact even when the full installer flow is blocked.

## Recommended Rebuild Checklist

Use this checklist the next time the build needs to be recreated:

1. Verify `mozilla-unified` exists and `comm` is mounted as a junction to this repo.
2. Verify `mozilla-unified\mozconfig` contains `--enable-project=comm/mail` and `MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird`.
3. Enter MozillaBuild with `USE_MINTTY=0`.
4. If setup needs to be refreshed, use `./mach --no-interactive bootstrap --application-choice browser`.
5. Update Gecko to `f2f75ecf8eb443871319273e7e39fb7f01b2581e` unless the Thunderbird checkout is intentionally changed to a newer compatible revision.
6. Run `./mach tb-rust vendor`.
7. Run `./mach clobber`.
8. Run `./mach build`.
9. Run `./mach package`.
10. Verify `obj-thunderbird\dist\bin\thunderbird.exe` and the ZIP package under `obj-thunderbird\dist`.

## Automation Script

A reusable PowerShell script is available at `C:\AI\thunderbird\thunderbird-desktop\rebuild-thunderbird.ps1`.

Default usage:

```powershell
Set-Location C:\AI\thunderbird\thunderbird-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-thunderbird.ps1
```

Dry run usage:

```powershell
Set-Location C:\AI\thunderbird\thunderbird-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-thunderbird.ps1 -DryRun
```

The script does the following:

- validates the Gecko root and MozillaBuild path
- ensures the `comm` junction points at this repository
- ensures `mozilla-unified\mozconfig` matches the Thunderbird configuration
- optionally bootstraps with the working `browser` alias
- updates Gecko to the known-good changeset from this build
- reruns the Rust vendor step
- clobbers, builds, and packages Thunderbird

Useful optional flags:

- `-SkipBootstrap`
- `-SkipGeckoUpdate`
- `-SkipVendor`
- `-SkipClobber`
- `-SkipPackage`

## Reuse Notes

If this repository stays at Thunderbird commit `762ee446617ca2b80655476bf1c6e56d4c0faa9d`, the safest default is to reuse the same Gecko revision and the same `mozconfig` from this document.

If Thunderbird is updated to a newer commit later, reevaluate Gecko alignment before assuming Gecko tip will work.