# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

A single Bash script (`build-appimage.sh`) that repackages the official Claude Desktop Windows installer into a Linux AppImage. It downloads the Windows `.exe`, extracts the Electron app bundle, replaces the Windows-only native module (`claude-native`) with a Linux stub, patches the title-bar detection logic in the minified renderer JS, and assembles the result using `appimagetool`.

## Running the build

```bash
# Basic build (auto-installs appimagetool to /usr/local/bin/ if absent)
./build-appimage.sh

# Key flags
./build-appimage.sh --appimagetool /path/to/appimagetool-x86_64.AppImage
./build-appimage.sh --bundle-electron       # embed Electron in the AppImage
./build-appimage.sh --keep-installer        # cache the .exe to avoid re-downloading
./build-appimage.sh --clean-cache           # wipe cache + build dir, then exit
./build-appimage.sh --claude-download-url <url>  # override installer URL
```

Required system packages: `7zip`, `wget`, `icoutils` (`wrestool`/`icotool`), `imagemagick` (`convert`), `nodejs`/`npm`, `npx`.  
Required npm packages: `asar` (installed globally by the script if missing), optionally `electron`.

## Updating for a new Claude version

The script auto-detects the latest version from the Squirrel RELEASES feed at `https://downloads.claude.ai/releases/win32/x64/RELEASES` — no manual URL update needed. The version is parsed from the downloaded nupkg filename.

To pin a specific version, set `CLAUDE_DOWNLOAD_URL` in the script to a direct `.nupkg` URL or a legacy Squirrel `.exe` URL. Note: the old feed at `storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64` is frozen at `0.14.10` and should not be used.

## Architecture

The entire build logic lives in `build-appimage.sh`. There are no source files beyond the script itself; everything generated during a build is ephemeral under `/tmp/claude-build/` (the `WORK_DIR`).

**Key steps and where they live in the script:**

| Step | Lines | What happens |
|------|-------|--------------|
| Dependency check | ~102–164 | Verifies `7z`, `wget`, `wrestool`, `icotool`, `convert`, `npx`; auto-installs `appimagetool` to `/usr/local/bin/` if absent |
| Electron resolution | ~182–237 | Finds or installs Electron (local `node_modules`, global, or bundled) |
| Download & extract | ~258–344 | Fetches latest nupkg from Squirrel RELEASES feed (or falls back to `.exe` if `CLAUDE_DOWNLOAD_URL` ends in `.exe`), uses `7z` once on the nupkg, parses the Claude version from the nupkg filename |
| Icon processing | ~307–346 | `wrestool` + `icotool` extract PNG icons at multiple sizes for hicolor theme dirs |
| `app.asar` patching | ~348–455 | Extracts with `npx asar`, injects the `claude-native` stub, copies Tray icons and i18n JSON, patches `MainWindowPage-*.js` with `sed` to remove the `!isWindows` title-bar guard, repacks |
| AppDir assembly | ~457–654 | Writes the stub `claude-native/index.js` again into the unpacked dir, creates `AppRun`, writes the `.desktop` entry |
| AppImage build | ~656–691 | Calls `appimagetool` with `ARCH=x86_64`, moves the result to `$CWD` |

**The `@ant/claude-native` stub** (written inline twice — once into the asar contents, once into the unpacked dir) is the core compat shim. It exports a frozen `KeyboardKey` enum with Linux-correct key codes and stubs out all Windows-only window-effect/notification/overlay APIs. The module was renamed from `claude-native` to `@ant/claude-native` in version 1.6608.0.

**Title-bar patch** (lines ~388–430): uses `sed -E` to transform `if(!VAR && VAR2)` → `if(VAR && VAR2)` in the minified `MainWindowPage-*.js` to enable the native title bar on non-Windows platforms.

**Caching**: when `--keep-installer` is set, the `.exe` is stored in `~/.cache/claude-desktop-appimage/` instead of `WORK_DIR`, surviving between runs.

**AppRun debug log**: the generated `AppRun` script appends runtime diagnostics (electron path resolution, launch command) to `/tmp/claude-apprun.log` — check there when the AppImage launches silently or fails to start.
