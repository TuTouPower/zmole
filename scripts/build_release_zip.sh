#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/artifacts/releases}"
derived_data="$repo_root/.scratch/release_derived"

if [[ "$output_dir" != /* ]]; then
    output_dir="$PWD/$output_dir"
fi

cd "$repo_root"
mkdir -p "$output_dir"

xcodegen generate
xcodebuild \
    -project Zmole.xcodeproj \
    -scheme Zmole \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    build

app="$derived_data/Build/Products/Release/Zmole.app"
test -d "$app"
/usr/bin/codesign --verify --deep --strict "$app"
signing_info="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
if ! printf '%s\n' "$signing_info" | /usr/bin/grep -Eq 'Signature=adhoc|flags=.*\(adhoc\)'; then
    printf '%s\n' "Release app must use an ad-hoc signature" >&2
    exit 1
fi

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
zip_path="$output_dir/Zmole-$version.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

printf '%s\n' "$zip_path"
