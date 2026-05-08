#!/bin/bash
set -e

# ==========================================================================================
# Change these variables to customize the build (or use command line arguments, see below)
# ==========================================================================================


# Path to appimagetool
APP_IMAGE_TOOL="/home/fabio/data/opt/appimagetool-x86_64.AppImage"

# Set to 1 if you want to bundle Electron with the AppImage (warning - this will increase the size of the AppImage)
# Set to 0 if you want to use the system Electron
ELECTRON_BUNDLED=0

# Set to 1 if you want to keep the installer outside the build directory to avoid re-downloading
KEEP_INSTALLER=0

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Directory where the build will be done
WORK_DIR="/tmp/claude-build"

# ==========================================================================================
# YOU SHOULD NOT NEED TO CHANGE ANYTHING BELOW THIS LINE
# ==========================================================================================

# Version of this build script
VERSION="0.2.0"


# Now read command line arguments to change the above variables
# with flags --appimagetool and --bundle-electron
# also supports -h and --help
while [[ $# -gt 0 ]]; do
    case $1 in
        --claude-download-url)
            CLAUDE_DOWNLOAD_URL="$2"
            shift 2
            ;;
        --appimagetool)
            APP_IMAGE_TOOL="$2"
            shift 2
            ;;
        --bundle-electron)
            ELECTRON_BUNDLED=1
            shift
            ;;
        --keep-installer)
            KEEP_INSTALLER=1
            shift
            ;;
        --clean-cache)
            CACHE_DIR="$HOME/.cache/claude-desktop-appimage"
            echo "🧹 Removing cache directory: $CACHE_DIR"
            rm -rf "$CACHE_DIR"
            echo "🧹 Removing build directory: $WORK_DIR"
            rm -rf "$WORK_DIR"
            echo "✓ Cache directory removed successfully"
            exit 0
            ;;
        -v|--version)
            echo "Claude Desktop AppImage Builder v$VERSION"
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [--appimagetool <path>] [--bundle-electron] [--keep-installer] [--clean-cache] [--version] [-h|--help]"
            echo "  --appimagetool <path>   Path to appimagetool (default: $APP_IMAGE_TOOL)"
            echo "  --bundle-electron       Bundle Electron with the AppImage (default: $ELECTRON_BUNDLED)"
            echo "  --keep-installer        Keep installer outside build directory to avoid re-downloading"
            echo "  --clean-cache           Remove cache directory and exit"
            echo "  --claude-download-url   URL to download the Claude Desktop installer (default: $CLAUDE_DOWNLOAD_URL)"
            echo "  -v, --version          Show version information"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done




CURRENT_DIR="$(pwd)"

# Check for Linux system
if [ ! -f "/etc/os-release" ]; then
    echo "❌ This script requires a Linux distribution"
    exit 1
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"

# Detect distro family and set package manager + package names accordingly
PKG_MANAGER="apt"
PKG_7ZIP="7zip"
PKG_IMAGEMAGICK="imagemagick"
PKG_NODEJS="nodejs npm"

DISTRO_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
DISTRO_ID_LIKE=$(grep "^ID_LIKE=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

if echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "opensuse|suse|sles"; then
    PKG_MANAGER="zypper install -y"
    PKG_IMAGEMAGICK="ImageMagick"
elif echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "fedora|rhel|centos|rocky|alma"; then
    PKG_MANAGER="dnf install -y"
elif echo "$DISTRO_ID $DISTRO_ID_LIKE" | grep -qiE "arch|manjaro"; then
    PKG_MANAGER="pacman -S --noconfirm"
    PKG_7ZIP="p7zip"
fi

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Check and install dependencies
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Check system package dependencies
for cmd in 7z wget wrestool icotool convert npx; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "7z")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL $PKG_7ZIP"
                ;;
            "wget")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget"
                ;;
            "wrestool"|"icotool")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils"
                ;;
            "convert")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL $PKG_IMAGEMAGICK"
                ;;
            "npx")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL $PKG_NODEJS"
                ;;
        esac
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    echo "Please install these dependencies with: "
    echo "sudo $PKG_MANAGER $DEPS_TO_INSTALL"
    exit 1
fi

# Check for appimagetool
if ! check_command $APP_IMAGE_TOOL; then
    echo "Installing appimagetool..."
    wget -O /tmp/appimagetool-x86_64.AppImage https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x /tmp/appimagetool-x86_64.AppImage
    echo "Sudo privileges required to install appimagetool to /usr/local/bin/"
    sudo mv /tmp/appimagetool-x86_64.AppImage /usr/local/bin/appimagetool
    if [ $? -eq 0 ]; then
        echo "✓ appimagetool installed successfully"
        APP_IMAGE_TOOL="/usr/local/bin/appimagetool"
    else
        echo "❌ Failed to install appimagetool. Please install it manually or update the APP_IMAGE_TOOL variable."
        exit 1
    fi
fi

# Check for electron - first local, then global
# Check for local electron in node_modules
if [ "$ELECTRON_BUNDLED" -eq 1 ]; then
    echo "Electron bundling is enabled. Installing electron locally..."
    # Create package.json if it doesn't exist
    if [ ! -f "package.json" ]; then
        echo '{"name":"claude-desktop-appimage","version":"1.0.0","private":true}' > package.json
    fi
    # Install electron locally
    npm install --save-dev electron
    if [ -f "$(pwd)/node_modules/.bin/electron" ]; then
        echo "✓ Local electron installed successfully for bundling"
        LOCAL_ELECTRON="$(pwd)/node_modules/.bin/electron"
        export PATH="$(pwd)/node_modules/.bin:$PATH"
    else
        echo "❌ Failed to install local electron. Cannot proceed with bundling."
        exit 1
    fi
else
    # Original electron detection logic for when bundling is disabled
    if [ -f "$(pwd)/node_modules/.bin/electron" ]; then
        echo "✓ local electron found in node_modules"
        LOCAL_ELECTRON="$(pwd)/node_modules/.bin/electron"
        export PATH="$(pwd)/node_modules/.bin:$PATH"
    elif ! check_command "electron"; then
        echo "Installing electron via npm..."
        # Try local installation first
        if [ -f "package.json" ]; then
            echo "Found package.json, installing electron locally..."
            npm install --save-dev electron
            if [ -f "$(pwd)/node_modules/.bin/electron" ]; then
                echo "✓ Local electron installed successfully"
                LOCAL_ELECTRON="$(pwd)/node_modules/.bin/electron"
                export PATH="$(pwd)/node_modules/.bin:$PATH"
            else
                # Fall back to global installation if local fails
                npm install -g electron
                if ! check_command "electron"; then
                    echo "Failed to install electron. Please install it manually:"
                    echo "npm install --save-dev electron"
                    exit 1
                fi
                echo "Global electron installed successfully"
            fi
        else
            # No package.json, try global installation
            npm install -g electron
            if ! check_command "electron"; then
                echo "Failed to install electron. Please install it manually:"
                echo "npm install --save-dev electron"
                exit 1
            fi
            echo "Global electron installed successfully"
        fi
    fi
fi

# Create working directories
APP_DIR="$WORK_DIR/ClaudeDesktop.AppDir"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/lib/claude-desktop"
mkdir -p "$APP_DIR/usr/share/applications"
mkdir -p "$APP_DIR/usr/share/icons/hicolor"

# Install asar if needed
if ! npm list -g asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Download Claude Windows installer
if [ "$KEEP_INSTALLER" -eq 1 ]; then
    # Use cache directory for persistent storage
    CACHE_DIR="$HOME/.cache/claude-desktop-appimage"
    mkdir -p "$CACHE_DIR"
    CLAUDE_EXE="$CACHE_DIR/Claude-Setup-x64.exe"
else
    CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
fi

if [ ! -e "$CLAUDE_EXE" ]; then
    echo "❌ Claude Desktop installer not found. Downloading..."
    echo "📥 Downloading Claude Desktop installer..."
    if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
        echo "❌ Failed to download Claude Desktop installer"
        exit 1
    fi
    echo "✓ Download complete"
else
    echo "✓ Claude Desktop installer already exists at: $CLAUDE_EXE"
fi

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Extract nupkg filename and version
NUPKG_PATH=$(find . -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG_PATH" ]; then
    echo "❌ Could not find AnthropicClaude nupkg file"
    exit 1
fi

# Extract version from the nupkg filename
VERSION=$(echo "$NUPKG_PATH" | grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full)')
if [ -z "$VERSION" ]; then
    echo "❌ Could not extract version from nupkg filename"
    exit 1
fi
echo "✓ Detected Claude version: $VERSION"

if ! 7z x -y "$NUPKG_PATH"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    exit 1
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
for size in 16 24 32 48 64 256; do
    icon_dir="$APP_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"

        # Copy the 256x256 icon to the AppDir root for AppImage
        if [ "$size" == "256" ]; then
            cp "${icon_files[$size]}" "$APP_DIR/.DirIcon"
            cp "${icon_files[$size]}" "$APP_DIR/claude-desktop.png"
        fi
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

cd "$WORK_DIR/electron-app"
npx asar extract app.asar app.asar.contents

# Replace native module with stub implementation
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy Tray icons
mkdir -p app.asar.contents/resources
mkdir -p app.asar.contents/resources/i18n

cp ../lib/net45/resources/Tray* app.asar.contents/resources/
cp ../lib/net45/resources/*-*.json app.asar.contents/resources/i18n/

echo "##############################################################"
echo "Removing "'!'" from 'if ("'!'"isWindows && isMainWindow) return null;'"
echo "detection flag to enable title bar"

echo "Current working directory: '$PWD'"

SEARCH_BASE="app.asar.contents/.vite/renderer/main_window/assets"
TARGET_PATTERN="MainWindowPage-*.js"

echo "Searching for '$TARGET_PATTERN' within '$SEARCH_BASE'..."
# Find the target file recursively (ensure only one matches)
TARGET_FILES=$(find "$SEARCH_BASE" -type f -name "$TARGET_PATTERN")
# Count non-empty lines to get the number of files found
NUM_FILES=$(echo "$TARGET_FILES" | grep -c .)

if [ "$NUM_FILES" -eq 0 ]; then
  echo "Error: No file matching '$TARGET_PATTERN' found within '$SEARCH_BASE'." >&2
  exit 1
elif [ "$NUM_FILES" -gt 1 ]; then
  echo "Error: Expected exactly one file matching '$TARGET_PATTERN' within '$SEARCH_BASE', but found $NUM_FILES." >&2
  echo "Found files:" >&2
  echo "$TARGET_FILES" >&2
  exit 1
else
  # Exactly one file found
  TARGET_FILE="$TARGET_FILES"
  echo "Found target file: $TARGET_FILE"

  # Create backup of original file
  cp "$TARGET_FILE" "$TARGET_FILE.backup"

  echo "Attempting to replace patterns like 'if(!VAR1 && VAR2)' with 'if(VAR1 && VAR2)' in $TARGET_FILE..."
  # Use character classes [a-zA-Z]+ to match minified variable names
  # Capture group 1: first variable name
  # Capture group 2: second variable name
  sed -i -E 's/if\(!([a-zA-Z]+)[[:space:]]*&&[[:space:]]*([a-zA-Z]+)\)/if(\1 \&\& \2)/g' "$TARGET_FILE"

  # Verification: Check if the original pattern structure still exists
  if ! grep -q -E 'if\(![a-zA-Z]+[[:space:]]*&&[[:space:]]*[a-zA-Z]+\)' "$TARGET_FILE"; then
    echo "Successfully replaced patterns like 'if(!VAR1 && VAR2)' with 'if(VAR1 && VAR2)' in $TARGET_FILE"
  else
    echo "Error: Failed to replace patterns like 'if(!VAR1 && VAR2)' in $TARGET_FILE. Check file contents." >&2
    exit 1
  fi
fi
echo "##############################################################"

# Repackage app.asar
npx asar pack app.asar.contents app.asar

# Create native module with keyboard constants
mkdir -p "$APP_DIR/usr/lib/claude-desktop/app.asar.unpacked/node_modules/claude-native"
cat > "$APP_DIR/usr/lib/claude-desktop/app.asar.unpacked/node_modules/claude-native/index.js" << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy app files
cp app.asar "$APP_DIR/usr/lib/claude-desktop/"
cp -r app.asar.unpacked "$APP_DIR/usr/lib/claude-desktop/"

# Copy local electron if available
if [ ! -z "$LOCAL_ELECTRON" ]; then
    if [ "$ELECTRON_BUNDLED" -eq 1 ]; then
        echo "Copying local electron to package..."
        cp -r "$(dirname "$LOCAL_ELECTRON")/.." "$APP_DIR/usr/lib/claude-desktop/node_modules/"
    fi
fi

# Create desktop entry
cat > "$APP_DIR/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=AppRun %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop
EOF

# Create AppRun script
cat > "$APP_DIR/AppRun" << EOF
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\$0")")"
export ELECTRON_PATH=""
export NODE_PATH=""

# Log AppRun execution for troubleshooting
echo "Starting Claude Desktop AppRun at \$(date)" >> /tmp/claude-apprun.log

# Set up environment
export PATH="\$HERE/usr/bin:\$HERE/usr/lib/claude-desktop/node_modules/.bin:\$PATH"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\$PATH"

# Find electron paths - this will help when electron is not bundled
if [ -f "\$HERE/usr/lib/claude-desktop/node_modules/.bin/electron" ]; then
    # Use bundled electron
    ELECTRON_PATH="\$HERE/usr/lib/claude-desktop/node_modules/.bin/electron"
    echo "Found bundled electron: \$ELECTRON_PATH" >> /tmp/claude-apprun.log
else
    # Log the PATH for debugging
    echo "PATH at startup: \$PATH" >> /tmp/claude-apprun.log

    # Search for node first
    NODE_PATHS=(
        "/usr/bin/node"
        "/usr/local/bin/node"
        "\$(find \$HOME/.nvm/versions/node -name node -type f -executable 2>/dev/null | head -n 1)"
    )

    for path in "\${NODE_PATHS[@]}"; do
        if [ -n "\$path" ] && [ -x "\$path" ]; then
            NODE_PATH="\$path"
            NODE_DIR="\$(dirname "\$path")"
            export PATH="\$NODE_DIR:\$PATH"
            echo "Found node: \$NODE_PATH" >> /tmp/claude-apprun.log
            break
        fi
    done

    # Search for electron in common locations
    ELECTRON_PATHS=(
        # Look in PATH with the updated PATH that includes node
        "\$(which electron 2>/dev/null)"
        # Check XDG desktop environment paths
        "/usr/bin/electron"
        "/usr/local/bin/electron"
        # Include common flatpak location
        "/var/lib/flatpak/exports/bin/io.atom.electron"
        # Check snap location
        "/snap/bin/electron"
        # Check NPM global installations
        "/usr/local/lib/node_modules/electron/dist/electron"
        "/usr/lib/node_modules/electron/dist/electron"
        # Try to directly access NVM electron with absolute path
        "\$(find \$HOME/.nvm/versions/node -name electron -type f -executable 2>/dev/null | head -n 1)"
        # Try distro-specific locations
        "/opt/electron/electron"
    )

    ELECTRON_PATH=\$(which electron 2>/dev/null || echo "")

    if [ -z "$ELECTRON_PATH" ]; then
        for path in "\${ELECTRON_PATHS[@]}"; do
            if [ -n "\$path" ] && [ -x "\$path" ]; then
                # Basic check if it's an ELF binary
                if file "\$path" 2>/dev/null | grep -q "ELF"; then
                    ELECTRON_PATH="\$path"
                    echo "Found electron binary: \$ELECTRON_PATH" >> /tmp/claude-apprun.log
                    break
                fi

                # If it's not an ELF binary but exists and is executable, it might be a script
                # Check if we found node earlier, which means we can run scripts
                if [ -n "\$NODE_PATH" ]; then
                    ELECTRON_PATH="\$path"
                    echo "Found electron script: \$ELECTRON_PATH (using node at \$NODE_PATH)" >> /tmp/claude-apprun.log
                    break
                fi
            fi
        done
    fi
fi

# If we still don't have a valid electron path, inform the user
if [ -z "\$ELECTRON_PATH" ] || [ ! -x "\$ELECTRON_PATH" ]; then
    ERROR_MSG="Error: Could not find electron executable. Please install electron globally with 'npm install -g electron' or rebuild with '--bundle-electron'."
    echo "\$ERROR_MSG" >> /tmp/claude-apprun.log
    echo "\$ERROR_MSG"

    # Log the attempted paths
    echo "System PATH: \$PATH" >> /tmp/claude-apprun.log
    echo "Attempted to find electron in:" >> /tmp/claude-apprun.log
    for path in "\${ELECTRON_PATHS[@]}"; do
        echo "  - \$path" >> /tmp/claude-apprun.log
    done

    # Create desktop notification for better visibility when launched from menu
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Claude Desktop Error" "Could not find Electron. Please install Electron or rebuild with --bundle-electron."
    fi

    exit 1
fi

# Run the electron app with the ASAR file (with sandbox disabled)
echo "Running: \$ELECTRON_PATH --no-sandbox \$HERE/usr/lib/claude-desktop/app.asar \$@" >> /tmp/claude-apprun.log

# If it's an NVM-installed electron or appears to be a script rather than a binary
if echo "\$ELECTRON_PATH" | grep -q "nvm" || file "\$ELECTRON_PATH" | grep -q "script"; then
    # For NVM or script-based Electron, make sure we have node in PATH and use --no-sandbox
    if [ -n "\$NODE_PATH" ]; then
        echo "Using Node.js: \$NODE_PATH" >> /tmp/claude-apprun.log
        NODE_DIR="\$(dirname "\$NODE_PATH")"
        export PATH="\$NODE_DIR:\$PATH"
    fi

    # Ensure we use no-sandbox option when using NVM
    echo "Using script-based Electron with --no-sandbox" >> /tmp/claude-apprun.log
    exec "\$ELECTRON_PATH" --no-sandbox "\$HERE/usr/lib/claude-desktop/app.asar" "\$@"
else
    # For direct binary Electron installations, also use no-sandbox
    echo "Using binary Electron with --no-sandbox" >> /tmp/claude-apprun.log
    exec "\$ELECTRON_PATH" --no-sandbox "\$HERE/usr/lib/claude-desktop/app.asar" "\$@"
fi
EOF
chmod +x "$APP_DIR/AppRun"

# Create desktop entry - fixed to properly handle URL protocols
cat > "$APP_DIR/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=AppRun %U
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop
EOF

# Build AppImage
echo "🖹 Building AppImage..."
cd "$WORK_DIR"
APPIMAGE_FILE="$WORK_DIR/Claude_Desktop-${VERSION}-x86_64.AppImage"

# Add ARCH environment variable to specify architecture
if ! ARCH=x86_64 $APP_IMAGE_TOOL "$APP_DIR" "$APPIMAGE_FILE"; then
    echo "❌ Failed to build AppImage"
    exit 1
fi

if [ -f "$APPIMAGE_FILE" ]; then
    chmod +x "$APPIMAGE_FILE"
    mv "$APPIMAGE_FILE" "$CURRENT_DIR"
    echo "✓ AppImage built successfully"
    echo "🎉 Done! You can now run the AppImage with: $(basename $APPIMAGE_FILE)"
    rm -Rf build
else
    echo "❌ AppImage file not found at expected location: $APPIMAGE_FILE"
    exit 1
fi
