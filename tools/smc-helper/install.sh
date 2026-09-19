#!/bin/bash
# SMC Helper Installation Script
# Installs smc-helper root-owned with a sudoers drop-in, so `sudo -n smc-helper`
# works without a password afterwards. This mirrors what the app does in
# PermissionsManager — keep the two in sync. The canonical values live in
# fan/Core/HelperInstallPaths.swift; mirror any change there here.

set -e

HELPER_NAME="smc-helper"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_PATH="$SCRIPT_DIR/$HELPER_NAME"
INSTALL_PATH="/usr/local/bin/$HELPER_NAME"
SUDOERS_PATH="/etc/sudoers.d/smc-fan-helper"

echo "🔧 SMC Helper Installer"
echo "======================"
echo ""

# Check if source exists
if [ ! -f "$SOURCE_PATH" ]; then
    echo "❌ Error: $SOURCE_PATH not found"
    echo "   Please build smc-helper first: make"
    exit 1
fi

echo "📦 Installing $HELPER_NAME to $INSTALL_PATH..."
echo "   This requires administrator privileges (one time only)."
echo ""

# root-owned, mode 755. Deliberately NOT setuid: the app always shells out
# through `sudo -n`, so setuid buys nothing, and without the drop-in every fan
# write would fall back to an AppleScript password prompt.
sudo mkdir -p /usr/local/bin /etc/sudoers.d
sudo cp -f "$SOURCE_PATH" "$INSTALL_PATH"
sudo chown root:wheel "$INSTALL_PATH"
sudo chmod 755 "$INSTALL_PATH"

printf '%%admin ALL=(root) NOPASSWD: %s\n' "$INSTALL_PATH" | sudo tee "$SUDOERS_PATH" > /dev/null
sudo chown root:wheel "$SUDOERS_PATH"
sudo chmod 440 "$SUDOERS_PATH"

# A malformed drop-in can break sudo system-wide, so validate before finishing.
sudo /usr/sbin/visudo -cf "$SUDOERS_PATH" > /dev/null

echo ""
echo "✅ Installation successful!"
echo ""
echo "   Helper:  $INSTALL_PATH"
echo "   Sudoers: $SUDOERS_PATH"
echo "   Owner: root, Permissions: -rwxr-xr-x (no setuid)"
echo ""
echo "   You will NOT need to enter your password again"
echo "   when controlling fan speeds."
echo ""
ls -la "$INSTALL_PATH"
