# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

A single Bash script (`build-appimage.sh`) that repackages the official Claude Desktop Windows installer into a Linux AppImage. It downloads the Windows `.exe`, extracts the Electron app bundle, replaces the Windows-only native module (`claude-native`) with a Linux stub, patches the title-bar detection logic in the minified renderer JS, and assembles the result using `appimagetool`.

## Running the build

```bash
# Basic build (requires appimagetool in PATH or at the hardcoded default path)
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

## Architecture

The entire build logic lives in `build-appimage.sh`. There are no source files beyond the script itself; everything generated during a build is ephemeral under `/tmp/claude-build/` (the `WORK_DIR`).

**Key steps and where they live in the script:**

| Step | Lines | What happens |
|------|-------|--------------|
| Dependency check | ~100–160 | Verifies `7z`, `wget`, `wrestool`, `icotool`, `convert`, `npx`; auto-installs `appimagetool` if absent |
| Electron resolution | ~161–216 | Finds or installs Electron (local `node_modules`, global, or bundled) |
| Download & extract | ~236–284 | Downloads the Windows `.exe`, uses `7z` twice (installer → nupkg → app files), parses the Claude version from the nupkg filename |
| Icon processing | ~287–325 | `wrestool` + `icotool` extract PNG icons at multiple sizes for hicolor theme dirs |
| `app.asar` patching | ~327–430 | Extracts with `npx asar`, injects the `claude-native` stub, copies Tray icons and i18n JSON, patches `MainWindowPage-*.js` with `sed` to remove the `!isWindows` title-bar guard, repacks |
| AppDir assembly | ~437–648 | Writes the stub `claude-native/index.js` again into the unpacked dir, creates `AppRun`, writes the `.desktop` entry |
| AppImage build | ~650–670 | Calls `appimagetool` with `ARCH=x86_64`, moves the result to `$CWD` |

**The `claude-native` stub** (written inline at lines ~337–377 and ~438–478) is the core compat shim. It exports a frozen `KeyboardKey` enum with Linux-correct key codes and stubs out all Windows-only window-effect/notification/overlay APIs.

**Title-bar patch** (lines ~388–430): uses `sed -E` to transform `if(!VAR && VAR2)` → `if(VAR && VAR2)` in the minified `MainWindowPage-*.js` to enable the native title bar on non-Windows platforms.

**Caching**: when `--keep-installer` is set, the `.exe` is stored in `~/.cache/claude-desktop-appimage/` instead of `WORK_DIR`, surviving between runs.
