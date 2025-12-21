#!/usr/bin/env bash
set -euo pipefail

# Nekotty をビルド、署名、公証、DMG作成するスクリプト

cd "$(dirname "$0")"

# リリースビルド
echo "Building Nekotty..."
swift build -c release

# .app バンドルを作成
echo "Creating app bundle..."
APP_DIR="dist/Nekotty.app"
rm -rf dist
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# バイナリをコピー
cp .build/release/Nekotty "${APP_DIR}/Contents/MacOS/"

# Info.plist をコピー
cp scripts/Info.plist "${APP_DIR}/Contents/"

# アイコンをコピー
cp scripts/AppIcon.icns "${APP_DIR}/Contents/Resources/"

# git情報を取得
git_sha=$(git rev-parse --short HEAD)
current_date=$(date +%Y%m%d%H%M%S)

# Info.plist のバージョンを更新
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${git_sha}" "${APP_DIR}/Contents/Info.plist"

echo "App bundle created: ${APP_DIR}"

# 署名
echo "Signing..."
bash scripts/sign-mac.sh \
  --app "${APP_DIR}" \
  --identity "Developer ID Application: KENGO NAKAJIMA (AD69GXLM5Y)" \
  --profile NekoTermNotary \
  --entitlements scripts/entitlements.plist

# DMG インストーラーを作成
dmg_path="dist/Nekotty_${git_sha}_${current_date}.dmg"
echo "Creating DMG..."
create-dmg \
  --volname "Nekotty" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Nekotty.app" 150 185 \
  --app-drop-link 450 185 \
  "${dmg_path}" \
  "${APP_DIR}"

echo "Done!"
echo "DMG created: ${dmg_path}"
