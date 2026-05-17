#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
app_name="ClipboardApp"
bundle_identifier="${BUNDLE_IDENTIFIER:-com.local.clipboard-manager}"
version="${VERSION:-0.1.0}"
icon_source="$PWD/Assets/AppIcon.png"
icon_name="AppIcon"
local_code_sign_identity="${LOCAL_CODE_SIGN_IDENTITY:-ClipboardApp Local Code Signing}"
code_sign_identity="${CODE_SIGN_IDENTITY:-}"
code_sign_keychain="${CODE_SIGN_KEYCHAIN:-}"
code_sign_timeout_seconds="${CODESIGN_TIMEOUT_SECONDS:-120}"
require_stable_code_signing="${REQUIRE_STABLE_CODE_SIGNING:-0}"

if [[ -z "$code_sign_identity" ]]; then
  find_identity_args=(-v -p codesigning)
  if [[ -n "$code_sign_keychain" ]]; then
    find_identity_args+=("$code_sign_keychain")
  fi

  if security find-identity "${find_identity_args[@]}" | grep -Fq "\"$local_code_sign_identity\""; then
    code_sign_identity="$local_code_sign_identity"
  elif [[ "$require_stable_code_signing" == "1" ]]; then
    echo "error: stable code signing required but identity '$local_code_sign_identity' was not found" >&2
    if [[ -n "$code_sign_keychain" ]]; then
      echo "error: searched keychain: $code_sign_keychain" >&2
    fi
    echo "error: run Scripts/setup-self-signed-signing.sh or set CODE_SIGN_IDENTITY to an available identity" >&2
    exit 1
  else
    code_sign_identity="-"
  fi
fi

swift build -c "$configuration" --product "$app_name" >&2
bin_path="$(swift build -c "$configuration" --show-bin-path)"
executable="$bin_path/$app_name"

if [[ ! -x "$executable" ]]; then
  echo "missing executable: $executable" >&2
  exit 1
fi

if [[ ! -f "$icon_source" ]]; then
  echo "missing icon source: $icon_source" >&2
  exit 1
fi

bundle_root="$PWD/.build/app-bundles/$configuration"
app_path="$bundle_root/$app_name.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
icon_work_root="$PWD/.build/app-icons/$configuration"
iconset_path="$icon_work_root/$icon_name.iconset"

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"

cp "$executable" "$macos_path/$app_name"

rm -rf "$iconset_path"
mkdir -p "$iconset_path"

make_icon() {
  local size="$1"
  local filename="$2"
  sips -z "$size" "$size" "$icon_source" --out "$iconset_path/$filename" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

iconutil -c icns "$iconset_path" -o "$resources_path/$icon_name.icns"

cat > "$contents_path/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Clipboard</string>
  <key>CFBundleExecutable</key>
  <string>$app_name</string>
  <key>CFBundleIconFile</key>
  <string>$icon_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_identifier</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Clipboard</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$version</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$code_sign_identity" == "-" ]]; then
  echo "warning: using ad-hoc signing; macOS Accessibility permission may need to be re-granted after code changes" >&2
else
  echo "signing with identity: $code_sign_identity" >&2
fi

run_codesign() {
  local identity="$1"
  local codesign_args=(--force --deep --sign "$identity")
  if [[ -n "$code_sign_keychain" ]]; then
    codesign_args+=(--keychain "$code_sign_keychain")
  fi
  codesign_args+=("$app_path")

  if [[ "$code_sign_timeout_seconds" == "0" ]]; then
    codesign "${codesign_args[@]}" >/dev/null
    return
  fi

  codesign "${codesign_args[@]}" >/dev/null &
  local pid="$!"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= code_sign_timeout_seconds )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

sign_status=0
run_codesign "$code_sign_identity" || sign_status=$?

if (( sign_status != 0 )); then
  if [[ "$code_sign_identity" == "-" ]]; then
    echo "error: ad-hoc codesign failed with status $sign_status" >&2
    exit "$sign_status"
  fi

  if (( sign_status == 124 )); then
    echo "warning: codesign with '$code_sign_identity' timed out after ${code_sign_timeout_seconds}s" >&2
  else
    echo "warning: codesign with '$code_sign_identity' failed with status $sign_status" >&2
  fi

  if [[ "$require_stable_code_signing" == "1" ]]; then
    echo "error: stable code signing required; set CODE_SIGN_IDENTITY=- to allow ad-hoc signing explicitly" >&2
    exit "$sign_status"
  fi

  echo "warning: falling back to ad-hoc signing; macOS Accessibility permission may need to be re-granted after code changes" >&2
  code_sign_identity="-"
  run_codesign "$code_sign_identity" || {
    sign_status=$?
    echo "error: fallback ad-hoc codesign failed with status $sign_status" >&2
    exit "$sign_status"
  }
fi

echo "$app_path"
