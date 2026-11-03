#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/.scratch/release_derived"

run_app=false
update_link=true

for arg in "$@"; do
    case "$arg" in
        --run)
            run_app=true
            ;;
        --no-link)
            update_link=false
            ;;
        *)
            ;;
    esac
done

if pgrep -x Zmole >/dev/null 2>&1; then
    pkill -x Zmole 2>/dev/null || true
    sleep 1
fi

arch="$(uname -m)"
if [[ "$arch" == "arm64" ]]; then
    target_dir="$repo_root/artifacts/mac-arm64"
else
    target_dir="$repo_root/artifacts/mac"
fi
target_app="$target_dir/Zmole.app"

cd "$repo_root"

xcodegen generate
xcodebuild \
    -project Zmole.xcodeproj \
    -scheme Zmole \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    build

app="$derived_data/Build/Products/Release/Zmole.app"
test -d "$app"

mkdir -p "$target_dir"
if [[ -e "$target_app" || -L "$target_app" ]]; then
    /bin/rm -rf "$target_app"
fi
/usr/bin/ditto "$app" "$target_app"

/usr/bin/codesign --verify --deep --strict "$target_app"
signing_info="$(/usr/bin/codesign -dv --verbose=4 "$target_app" 2>&1)"
if ! printf '%s\n' "$signing_info" | /usr/bin/grep -qF 'Authority=Zmole Local Signing'; then
    printf '%s\n' "Release app must be signed with \"Zmole Local Signing\"; run scripts/setup_signing_identity.sh" >&2
    exit 1
fi

if [[ "$update_link" == true ]]; then
    apps_link="/Applications/Zmole.app"
    if [[ -L "$apps_link" || ! -e "$apps_link" ]]; then
        /bin/rm -f "$apps_link" 2>/dev/null || true
        ln -s "$target_app" "$apps_link" 2>/dev/null || true
    fi
fi

printf '%s\n' "$target_app"

if [[ "$run_app" == true ]]; then
    open "$target_app"
fi
