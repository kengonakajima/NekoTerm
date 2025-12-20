#!/usr/bin/env bash

# このスクリプトは、Electronアプリ(.app)をDeveloper ID Applicationで署名し、
# notarytoolで公証し、最後にstapleまで実行する。
# macOS環境でのみ使用可能。Keychainには事前に証明書とnotarytool用の
# Keychainプロファイルをセットしておくこと。

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/sign-mac.sh \
    --app <path/to/MyApp.app> \
    --identity "Developer ID Application: Example (TEAMID)" \
    --profile <NotaryProfileName> \
    [--entitlements path/to/entitlements.plist] \
    [--archive path/to/output.zip] \
    [--keychain path/to/login.keychain-db]

Required:
  --app         署名対象の.appパス
  --identity    Keychain上のDeveloper ID Application署名者名
  --profile     `xcrun notarytool store-credentials` で登録済みのKeychainプロファイル名

Optional:
  --entitlements  entitlementsファイル（必要なければ省略）
  --archive       公証提出用に作成するzipの出力先。省略時は <app名>.zip
  --keychain      notarytoolで使用するKeychainパス。login.keychain-db以外を使うときに指定

実行フロー:
  1. codesignで署名
  2. codesign / spctl で検証
  3. dittoでzipを作成
  4. xcrun notarytool submit --wait
  5. xcrun stapler staple
  6. spctlとstapler validateで最終確認

例:
  scripts/sign-mac.sh \
    --app dist/Supercat-darwin-arm64/Supercat.app \
    --identity "Developer ID Application: Your Name (AD69GXLM5Y)" \
    --profile SupercatNotary \
    --entitlements entitlements.plist
EOF
}

# 単純なログ出力
log() {
  printf '[sign-mac] %s\n' "$*"
}

# 引数パース
APP_PATH=""
IDENTITY=""
PROFILE=""
ENTITLEMENTS=""
ARCHIVE_PATH=""
KEYCHAIN_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS="$2"
      shift 2
      ;;
    --archive)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --keychain)
      KEYCHAIN_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$IDENTITY" || -z "$PROFILE" ]]; then
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  printf '指定された.appが見つかりません: %s\n' "$APP_PATH" >&2
  exit 1
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  APP_BASENAME="$(basename "$APP_PATH")"
  ARCHIVE_PATH="${APP_BASENAME%.app}.zip"
fi

# 必要コマンドの存在チェック
for cmd in codesign xcrun spctl ditto file; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$cmd" >&2
    exit 1
  fi
done

# 署名対象の中でバイナリが多い順に並べる（ヘルパーアプリやFrameworkを含めて順番に署名）
log "Signing nested components under $APP_PATH"
SIGN_TARGETS=()
while IFS= read -r target; do
  SIGN_TARGETS+=("$target")
done < <(find "$APP_PATH" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) -print 2>/dev/null | sort)

codesign_flags=(--force --options runtime --timestamp --sign "$IDENTITY")
if [[ -n "$ENTITLEMENTS" ]]; then
  codesign_flags+=(--entitlements "$ENTITLEMENTS")
fi

for target in "${SIGN_TARGETS[@]}"; do
  if [[ ! -e "$target" ]]; then
    continue
  fi
  if ! file -b "$target" 2>/dev/null | grep -q "Mach-O"; then
    continue
  fi
  log "codesign nested binary: $target"
  codesign "${codesign_flags[@]}" "$target"
done

log "codesign bundle: $APP_PATH"
codesign "${codesign_flags[@]}" --deep "$APP_PATH"

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if spctl -a -t exec -vv "$APP_PATH"; then
  log "Gatekeeper accepted bundle before notarization (already stapled?)"
else
  log "Gatekeeper rejected bundle prior to notarization (expected)"
fi

log "Preparing archive for notarization"
NOTARY_TMP_DIR="$(mktemp -d)"
NOTARY_ARCHIVE="$NOTARY_TMP_DIR/notary-submission.zip"

# dittoでzip化（公証提出用）。--keepParentで.appフォルダを保持
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ARCHIVE"

log "Submitting to notary service (profile: $PROFILE)"
NOTARY_OUTPUT="$(mktemp)"
cleanup() {
  rm -f "$NOTARY_OUTPUT"
  rm -rf "$NOTARY_TMP_DIR"
}
trap cleanup EXIT

notary_cmd=(xcrun notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$PROFILE" --wait --output-format json)
if [[ -n "$KEYCHAIN_PATH" ]]; then
  notary_cmd+=(--keychain "$KEYCHAIN_PATH")
fi
"${notary_cmd[@]}" >"$NOTARY_OUTPUT"

log "Notary response:"
cat "$NOTARY_OUTPUT"

STATUS="$(/usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",""))' <"$NOTARY_OUTPUT" 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  printf 'Notary submission did not finish with Accepted status. Status: %s\n' "$STATUS" >&2
  exit 1
fi

log "Stapling ticket onto $APP_PATH"
xcrun stapler staple "$APP_PATH"

log "Final Gatekeeper check"
spctl -a -t exec -vv "$APP_PATH"
xcrun stapler validate "$APP_PATH"

log "Creating distribution archive $ARCHIVE_PATH"
if [[ -e "$ARCHIVE_PATH" ]]; then
  log "Removing existing archive $ARCHIVE_PATH"
  rm -f "$ARCHIVE_PATH"
fi
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"

log "Done. Archive: $ARCHIVE_PATH"
