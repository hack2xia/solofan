#!/bin/bash
# SoloFan Quick Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/mohamadlounnas/ffan/main/scripts/install.sh | bash

set -e

REPO="mohamadlounnas/ffan"
APP_NAME="SoloFan"

echo "🌬️  SoloFan Installation"
echo "========================"
echo ""

LATEST_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    echo "❌ Failed to fetch latest version"
    exit 1
fi

VERSION="${LATEST_TAG#v}"
ARCHIVE="solofan-v${VERSION}-macos.zip"

echo "📥 Downloading SoloFan ${LATEST_TAG}..."
curl -L "https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ARCHIVE}" -o "/tmp/${ARCHIVE}"

echo "📦 Extracting..."
cd /tmp
unzip -q "${ARCHIVE}"

echo "🔄 Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
mv "${APP_NAME}.app" /Applications/

# Install the helper the same way the app does (see PermissionsManager):
# root-owned, mode 755, plus a sudoers drop-in so `sudo -n smc-helper ...` runs
# without a password. Deliberately NOT setuid: the app always shells out through
# `sudo -n`, so setuid buys nothing, and without the drop-in every fan write
# would fall back to an AppleScript password prompt.
HELPER="/usr/local/bin/smc-helper"
SUDOERS="/etc/sudoers.d/smc-fan-helper"

echo "🔧 Installing helper tool (requires password)..."
sudo mkdir -p /usr/local/bin /etc/sudoers.d
sudo cp -f "/Applications/${APP_NAME}.app/Contents/Resources/smc-helper" "$HELPER"
sudo chown root:wheel "$HELPER"
sudo chmod 755 "$HELPER"

printf '%%admin ALL=(root) NOPASSWD: %s\n' "$HELPER" | sudo tee "$SUDOERS" > /dev/null
sudo chown root:wheel "$SUDOERS"
sudo chmod 440 "$SUDOERS"

# A malformed drop-in can break sudo system-wide, so validate before finishing.
sudo /usr/sbin/visudo -cf "$SUDOERS" > /dev/null

echo "🧹 Cleaning up..."
rm "/tmp/${ARCHIVE}"

echo ""
echo "✅ Installation complete!"
echo "🚀 Launching SoloFan..."
echo ""

open "/Applications/${APP_NAME}.app"
