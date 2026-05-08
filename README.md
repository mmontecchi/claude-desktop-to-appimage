# Claude Desktop for Linux (AppImage)

This project was inspired by [aaddrick claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) for running Claude Desktop natively on Linux. Their work provided valuable insights into the application's structure and the native bindings implementation.

The main changes are:

- No `sudo` required (if some dependencies are missing, it will guide you to install them)
- AppImage generation instead of a `.deb` package

> NOTE: A big part of this README is taken by [aaddrick claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) README

**_THIS IS AN UNOFFICIAL BUILD SCRIPT!_**

If you run into an issue with this build script, make an issue here. Don't bug Anthropic about it - they already have enough on their plates.

# Supports MCP!

Location of the MCP-configuration file is: `~/.config/Claude/claude_desktop_config.json`

![image](https://github.com/user-attachments/assets/93080028-6f71-48bd-8e59-5149d148cd45)

Supports the Ctrl+Alt+Space popup!
![image](https://github.com/user-attachments/assets/1deb4604-4c06-4e4b-b63f-7f6ef9ef28c1)

Supports the Tray menu! (Screenshot of running on KDE)
![image](https://github.com/user-attachments/assets/ba209824-8afb-437c-a944-b53fd9ecd559)

# How to use it

## 1. Download the repo

```bash
# Clone this repository
git clone https://github.com/mmontecchi/claude-desktop-to-appimage.git
cd claude-desktop-to-appimage

# Build the AppImage
./build-appimage.sh

# The script will automatically:
# - Check for required dependencies (installation must be done by the user)
# - Download and extract resources from the Windows version
# - Create a proper AppImage
```

Requirements:

- Linux distribution (Debian/Ubuntu, openSUSE/SUSE, Fedora/RHEL, Arch/Manjaro)
- Node.js >= 12.0.0 and npm

## Command line

The script accepts the following command line arguments:

```bash
Usage: ./build-appimage.sh [--appimagetool <path>] [--bundle-electron] [--keep-installer] [--clean-cache] [--version] [-h|--help]
  --appimagetool <path>   Path to appimagetool (default: /usr/local/bin/appimagetool)
  --bundle-electron       Bundle Electron with the AppImage (default: 0)
  --keep-installer        Keep installer outside build directory to avoid re-downloading
  --clean-cache           Remove cache directory and exit
  --claude-download-url   Direct URL to a .nupkg or Squirrel .exe (default: auto-detect from RELEASES feed)
  -v, --version          Show version information
  -h, --help             Show this help message
```

You can run the script without arguments, and it will use the default values.

```bash
./build-appimage.sh
```

Or you can specify some options:

- `--appimagetool <path>`: Specify the path to the `appimagetool` executable. If not found, the script will automatically download and install it to `/usr/local/bin/appimagetool`.
- `--bundle-electron`: Bundle Electron with the AppImage (default is `0`, meaning it will not bundle Electron, and will use the system-installed version if available (the AppImage will be smaller, but it may only work on your system)).
- `--keep-installer`: Cache the downloaded nupkg in `~/.cache/claude-desktop-appimage/` to avoid re-downloading on subsequent builds. Remember to run `--clean-cache` when you finish testing.
- `--clean-cache`: Remove the cache directory and exit. This is useful if you want to start fresh without any cached data.
- `--claude-download-url <url>`: Override the auto-detected download with a direct URL to a specific `.nupkg` or a legacy Squirrel `.exe`. Leave unset to always pull the latest version automatically.
- `-v, --version`: Show version information of the script.
- `-h, --help`: Show the help message with available options.

# How it works

Claude Desktop is an Electron application packaged as a Windows executable. Our build script performs several key operations to make it work on Linux:

1. Auto-detects the latest version from Anthropic's Squirrel RELEASES feed and downloads the nupkg directly
2. Unpacks the `app.asar` archive containing the application code
3. Replaces the Windows-specific native module with a Linux-compatible stub
4. Repackages everything into a portable AppImage

The process works because Claude Desktop is largely cross-platform, with only one platform-specific component that needs replacement.

## The Native Module Challenge

The only platform-specific component is a native Node.js module (`@ant/claude-native`). This module provides system-level functionality like:

- Keyboard input handling
- Window management
- System tray integration
- Monitor information

Our build script replaces this Windows-specific module with a Linux-compatible stub that:

1. Provides the same API surface to maintain compatibility
2. Implements keyboard handling using the correct key codes from the reference implementation
3. Stubs out unnecessary Windows-specific functionality
4. Maintains critical features like the Ctrl+Alt+Space popup and system tray

The replacement module is carefully designed to match the original API while providing Linux-native functionality where needed. This approach allows the rest of the application to run unmodified, believing it's still running on Windows.

## Build Process Details

The build script (`build-appimage.sh`) handles the entire process:

1. Detects the Linux distribution family and checks for required dependencies (suggesting the correct install command for apt/zypper/dnf/pacman)
2. Fetches the Squirrel RELEASES manifest from `downloads.claude.ai` and downloads the latest full nupkg
3. Extracts the application resources from the nupkg
4. Processes icons for Linux desktop integration
5. Unpacks and modifies the `app.asar`:
   - Replaces `@ant/claude-native` with the Linux stub
   - Updates keyboard key mappings
   - Preserves all other functionality
6. Creates a proper AppImage with:
   - Desktop entry for application menus
   - System-wide icon integration
   - Proper dependency management
   - Post-install configuration

# License

The build script in this repository is licensed under MIT License.

See [LICENSE-MIT](LICENSE-MIT) for details.

The Claude Desktop application, not included in this repository, is likely covered by [Anthropic's Consumer Terms](https://www.anthropic.com/legal/consumer-terms).
