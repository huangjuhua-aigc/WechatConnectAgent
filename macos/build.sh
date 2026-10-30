#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$ROOT/../dist/macos-build}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
APP="$OUTPUT/ChatInbox.app"
if [ -e "$APP" ]; then echo "Output already exists: $APP" >&2; exit 1; fi
cd "$ROOT"
APP_BINARIES=()
SHARE_BINARIES=()
for ARCH in arm64 x86_64; do
  SCRATCH="$ROOT/.build/release-$ARCH"
  swift build -c release --triple "$ARCH-apple-macosx" --scratch-path "$SCRATCH" --product ChatInbox
  swift build -c release --triple "$ARCH-apple-macosx" --scratch-path "$SCRATCH" --product ChatInboxShare
  BIN="$(swift build -c release --triple "$ARCH-apple-macosx" --scratch-path "$SCRATCH" --show-bin-path)"
  APP_BINARIES+=("$BIN/ChatInbox")
  SHARE_BINARIES+=("$BIN/ChatInboxShare")
done
EXTENSION="$APP/Contents/PlugIns/ChatInboxShare.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXTENSION/Contents/MacOS"
lipo -create "${APP_BINARIES[@]}" -output "$APP/Contents/MacOS/ChatInbox"
lipo -create "${SHARE_BINARIES[@]}" -output "$EXTENSION/Contents/MacOS/ChatInboxShare"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Share-Info.plist" "$EXTENSION/Contents/Info.plist"
cp "$ROOT/../skills/wechat-chat-select/receiver/THIRD_PARTY_NOTICES.txt" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
plutil -lint "$APP/Contents/Info.plist" "$EXTENSION/Contents/Info.plist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT/Resources/Share.entitlements" "$EXTENSION"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/ChatInbox" -verify_arch arm64 x86_64
lipo "$EXTENSION/Contents/MacOS/ChatInboxShare" -verify_arch arm64 x86_64
nm -u "$EXTENSION/Contents/MacOS/ChatInboxShare" > "$OUTPUT/extension-symbols.txt"
grep -q '_NSExtensionMain' "$OUTPUT/extension-symbols.txt"
echo "Built universal macOS app: $APP"
if [ "$SIGN_IDENTITY" = '-' ]; then echo 'Ad-hoc test build; not Developer ID signed or notarized.'; fi
