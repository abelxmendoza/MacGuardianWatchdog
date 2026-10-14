#!/bin/bash
set -e

APP_NAME="MacGuardian Suite"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"

echo "▸ Building Swift package..."
cd "$ROOT_DIR"
swift build -c release
# Ask SwiftPM where it put the binary - the folder differs between toolchains
# (.build/arm64-apple-macosx/release vs .build/out/Products/Release).
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/Resources/images"

echo "▸ Copying executable..."
cp "$BIN_DIR/MacGuardianSuiteUI" "$APP_PATH/Contents/MacOS/"

echo "▸ Copying icon..."
if [ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
    echo "   ✔ Icon copied"
else
    echo "   ⚠️  Warning: Icon not found at $PROJECT_ROOT/Resources/AppIcon.icns"
fi

echo "▸ Copying logo images..."
# Copy brighter logo (priority for dock/app display)
if [ -f "$ROOT_DIR/Resources/images/MacGuardianlogo-brighter.jpg" ]; then
    cp "$ROOT_DIR/Resources/images/MacGuardianlogo-brighter.jpg" "$APP_PATH/Contents/Resources/MacGuardianlogo-brighter.jpg"
    cp "$ROOT_DIR/Resources/images/MacGuardianlogo-brighter.jpg" "$APP_PATH/Contents/Resources/images/MacGuardianlogo-brighter.jpg"
    echo "   ✔ MacGuardianlogo-brighter.jpg copied"
fi
if [ -f "$ROOT_DIR/Resources/images/MacGlogo.png" ]; then
    cp "$ROOT_DIR/Resources/images/MacGlogo.png" "$APP_PATH/Contents/Resources/MacGlogo.png"
    cp "$ROOT_DIR/Resources/images/MacGlogo.png" "$APP_PATH/Contents/Resources/images/MacGlogo.png"
    echo "   ✔ MacGlogo.png copied"
fi
if [ -f "$ROOT_DIR/Resources/images/MacGuardianLogo.png" ]; then
    cp "$ROOT_DIR/Resources/images/MacGuardianLogo.png" "$APP_PATH/Contents/Resources/MacGuardianLogo.png"
    cp "$ROOT_DIR/Resources/images/MacGuardianLogo.png" "$APP_PATH/Contents/Resources/images/MacGuardianLogo.png"
    echo "   ✔ MacGuardianLogo.png copied"
fi

echo "▸ Writing Info.plist..."
cat > "$APP_PATH/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MacGuardian Suite</string>

    <key>CFBundleDisplayName</key>
    <string>MacGuardian Suite</string>

    <key>CFBundleIdentifier</key>
    <string>com.omegatech.macguardian</string>

    <key>CFBundleExecutable</key>
    <string>MacGuardianSuiteUI</string>

    <key>CFBundleVersion</key>
    <string>1.0</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>LSUIElement</key>
    <false/>

    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 MacGuardian Suite</string>

    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

# Record where this checkout lives so the app finds its scripts wherever the
# project was downloaded to (read by RepoLocator in AppState.swift).
/usr/libexec/PlistBuddy -c "Add :MGRepositoryPath string $PROJECT_ROOT" "$APP_PATH/Contents/Info.plist"

echo "▸ Creating PkgInfo..."
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

echo "▸ Signing app bundle (local ad-hoc signature)..."
/usr/bin/codesign --force --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

echo ""
echo "✔ Build complete: $APP_PATH"

# Install over the copy in /Applications so the Dock icon opens this build.
# Set SKIP_INSTALL=1 to only build.
INSTALL_PATH="/Applications/$APP_NAME.app"
if [ "${SKIP_INSTALL:-0}" != "1" ]; then
    echo "▸ Installing to $INSTALL_PATH..."
    if pgrep -x MacGuardianSuiteUI >/dev/null; then
        echo "   Quitting running copy..."
        pkill -x MacGuardianSuiteUI || true
        sleep 1
    fi
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    echo "   ✔ Installed"
fi

echo ""
echo "🚀 To launch:"
echo "   open \"$INSTALL_PATH\""
echo ""
echo "💡 To force macOS to reload icon cache:"
echo "   killall Finder"
echo "   killall Dock"
