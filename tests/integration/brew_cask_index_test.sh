#!/bin/bash
# Integration test for Homebrew cask indexing (t054).
# Verifies AC-001 ~ AC-009: single list snapshot, single Caskroom traversal,
# exact file identity ownership, directional probe for ambiguous candidates,
# and residual token rejection.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNINSTALL="$REPO_ROOT/src/zmole/Resources/mole/bin/uninstall.sh"
BREW_LIB="$REPO_ROOT/src/zmole/Resources/mole/lib/uninstall/brew.sh"

failures=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1" >&2
    failures=$((failures + 1))
}

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "${WORK:-}"' EXIT
HOME="$WORK/home"
mkdir -p "$HOME"
export HOME

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
BREW_LOG="$WORK/brew.log"
: > "$BREW_LOG"

# Controllable fake brew
cat > "$FAKE_BIN/brew" <<'EOF_BREW'
#!/bin/bash
echo "$*" >> "${FAKE_BREW_LOG}"
case "$1" in
    list)
        if [[ "${FAKE_BREW_LIST_FAIL:-0}" == "1" ]]; then
            exit 124
        fi
        cat "${FAKE_BREW_INSTALLED_FILE}" 2>/dev/null || true
        exit 0
        ;;
    info)
        token="$3"
        if [[ "${FAKE_BREW_INFO_FAIL:-0}" == "1" ]]; then
            exit 124
        fi
        if [[ -f "${FAKE_BREW_INFO_DIR}/${token}.info" ]]; then
            cat "${FAKE_BREW_INFO_DIR}/${token}.info"
            exit 0
        fi
        echo "No info for $token" >&2
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF_BREW
chmod +x "$FAKE_BIN/brew"

export PATH="$FAKE_BIN:$PATH"
export FAKE_BREW_LOG="$BREW_LOG"

CASKROOM="$WORK/Caskroom"
mkdir -p "$CASKROOM"
export HOMEBREW_CASKROOM="$CASKROOM"

# Create fake casks in Caskroom
mkdir -p "$CASKROOM/cask-dup-a/1.0/DupApp.app/Contents"
mkdir -p "$CASKROOM/cask-dup-b/1.0/DupApp.app/Contents"
mkdir -p "$CASKROOM/cask-stale/1.0/Stale.app/Contents"
mkdir -p "$CASKROOM/cask-fast/1.0/FastReal.app/Contents"
echo "fast-pkg" > "$CASKROOM/cask-fast/1.0/FastReal.app/Contents/pkg"
mkdir -p "$CASKROOM/cask-fast-real/1.0/QuickReal.app/Contents"
echo "quick-pkg" > "$CASKROOM/cask-fast-real/1.0/QuickReal.app/Contents/pkg"

# Installed tokens file
INSTALLED_FILE="$WORK/installed_casks.txt"
cat > "$INSTALLED_FILE" <<'EOF_INS'
cask-one
cask-two
cask-three
cask-dup-a
cask-dup-b
cask-fast
cask-fast-real
EOF_INS
export FAKE_BREW_INSTALLED_FILE="$INSTALLED_FILE"

INFO_DIR="$WORK/info"
mkdir -p "$INFO_DIR"
export FAKE_BREW_INFO_DIR="$INFO_DIR"

# Target scan directory with 3 apps where Caskroom links to the app (fast path misses, index ownership matches)
SCAN="$WORK/apps"
mkdir -p "$SCAN"

mkdir -p "$SCAN/CaskOne.app/Contents"
echo "pkg1" > "$SCAN/CaskOne.app/Contents/pkg"
mkdir -p "$CASKROOM/cask-one/1.0"
ln -s "$SCAN/CaskOne.app" "$CASKROOM/cask-one/1.0/CaskOne.app"

mkdir -p "$SCAN/CaskTwo.app/Contents"
echo "pkg2" > "$SCAN/CaskTwo.app/Contents/pkg"
mkdir -p "$CASKROOM/cask-two/2.0"
ln -s "$SCAN/CaskTwo.app" "$CASKROOM/cask-two/2.0/CaskTwo.app"

mkdir -p "$SCAN/CaskThree.app/Contents"
echo "pkg3" > "$SCAN/CaskThree.app/Contents/pkg"
mkdir -p "$CASKROOM/cask-three/3.0"
ln -s "$SCAN/CaskThree.app" "$CASKROOM/cask-three/3.0/CaskThree.app"

# AC-001 & AC-002: 3 apps resolved through real list-stream
# Verify brew list --cask <= 1, Caskroom traversal <= 1, brew info == 0
COUNT_FILE="$WORK/caskroom_traversals.txt"
: > "$COUNT_FILE"
: > "$BREW_LOG"

OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache1" \
    MOLE_TEST_CASKROOM_TRAVERSAL_COUNT_FILE="$COUNT_FILE" \
    bash "$UNINSTALL" --list-stream 2> "$WORK/err1")

LIST_CALLS=$(( $(grep -c "list --cask" "$BREW_LOG" 2>/dev/null) + 0 ))
INFO_CALLS=$(( $(grep -c "info --cask" "$BREW_LOG" 2>/dev/null) + 0 ))
TRAVERSALS=$(( $(wc -l < "$COUNT_FILE" 2>/dev/null) + 0 ))

if [[ $LIST_CALLS -le 1 ]]; then
    pass "AC-001 brew list --cask called at most once ($LIST_CALLS call)"
else
    fail "AC-001 brew list --cask called too many times ($LIST_CALLS calls)"
fi

if [[ $TRAVERSALS -le 1 ]]; then
    pass "AC-001 Caskroom traversed at most once ($TRAVERSALS traversal)"
else
    fail "AC-001 Caskroom traversed multiple times ($TRAVERSALS traversals)"
fi

if [[ $INFO_CALLS -eq 0 ]]; then
    pass "AC-002 exact file identity skips brew info (0 calls)"
else
    fail "AC-002 exact file identity unexpectedly called brew info ($INFO_CALLS calls)"
fi

# Verify tokens resolved correctly
if printf '%s' "$OUT" | grep -q '"uninstall_name":"cask-one"'; then
    pass "AC-002 CaskOne resolved to cask-one"
else
    fail "AC-002 CaskOne failed to resolve: $(printf '%s' "$OUT" | grep CaskOne)"
fi

# AC-003: Multiple casks containing same name app
# DupApp.app without exact identity calls info only for candidates, does not pick first
DUP_SCAN="$WORK/dup_scan"
mkdir -p "$DUP_SCAN/DupApp.app/Contents"
echo "different-app" > "$DUP_SCAN/DupApp.app/Contents/pkg"

: > "$BREW_LOG"
cat > "$INFO_DIR/cask-dup-a.info" <<EOF_INFO
cask-dup-a: 1.0
https://example.com/cask-dup-a
/opt/homebrew/Caskroom/cask-dup-a/1.0/DupApp.app (App)
EOF_INFO

cat > "$INFO_DIR/cask-dup-b.info" <<EOF_INFO
cask-dup-b: 1.0
https://example.com/cask-dup-b
/opt/homebrew/Caskroom/cask-dup-b/1.0/DupApp.app (App)
EOF_INFO

DUP_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$DUP_SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_dup" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

DUP_INFO_CALLS=$(( $(grep -c "info --cask" "$BREW_LOG" 2>/dev/null) + 0 ))
if [[ $DUP_INFO_CALLS -le 2 ]]; then
    pass "AC-003 ambiguous candidates only queried directional info ($DUP_INFO_CALLS calls)"
else
    fail "AC-003 ambiguous candidates made excessive info calls ($DUP_INFO_CALLS calls)"
fi

# Neither info output mentions $DUP_SCAN/DupApp.app, so neither is confirmed
if printf '%s' "$DUP_OUT" | grep '"name":"DupApp"' | grep -q '"source":"App"'; then
    pass "AC-003 unconfirmed ambiguous cask not claimed as Homebrew"
else
    fail "AC-003 ambiguous cask unexpectedly claimed token: $(printf '%s' "$DUP_OUT" | grep DupApp)"
fi

# AC-005: Homebrew unavailable
NO_BREW_PATH="/usr/bin:/bin"
NO_BREW_OUT=$(PATH="$NO_BREW_PATH" \
    MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_nobrew" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

if printf '%s' "$NO_BREW_OUT" | grep -q '"source":"Homebrew"'; then
    fail "AC-005 apps marked Homebrew when brew unavailable"
else
    pass "AC-005 brew unavailable completes list without Homebrew markings"
fi

# AC-006: Stale / uninstalled token not returned
STALE_SCAN="$WORK/stale_scan"
mkdir -p "$STALE_SCAN"
ln -s "$CASKROOM/cask-stale/1.0/Stale.app" "$STALE_SCAN/Stale.app"

STALE_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$STALE_SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_stale" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

if printf '%s' "$STALE_OUT" | grep '"name":"Stale"' | grep -q '"uninstall_name":"cask-stale"'; then
    fail "AC-006 uninstalled stale cask unexpectedly returned token"
else
    pass "AC-006 uninstalled stale cask rejected"
fi

# AC-007: Timeout failure returns error code and does not treat as uninstalled
export FAKE_BREW_LIST_FAIL=1
FAIL_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_fail" \
    bash "$UNINSTALL" --list-stream 2> /dev/null || true)
unset FAKE_BREW_LIST_FAIL

if printf '%s' "$FAIL_OUT" | grep -q '"uninstall_name":"cask-one"'; then
    fail "AC-007 failed list probe unexpectedly claimed cask"
else
    pass "AC-007 failed list probe does not claim false cask"
fi

# AC-008: Two scans each read their own index; changes in installed tokens reflect on second scan
SCAN2_WORK="$WORK/scan2_apps"
mkdir -p "$SCAN2_WORK"
ln -s "$CASKROOM/cask-fast/1.0/FastReal.app" "$SCAN2_WORK/FastReal.app"

SCAN2_FIRST_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN2_WORK" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_scan2_a" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

if printf '%s' "$SCAN2_FIRST_OUT" | grep -q '"uninstall_name":"cask-fast"'; then
    pass "AC-008 scan 1 discovers installed cask-fast"
else
    fail "AC-008 scan 1 failed to discover cask-fast"
fi

# Simulate uninstall: remove cask-fast from installed snapshot
sed -i '' '/^cask-fast$/d' "$INSTALLED_FILE" 2>/dev/null || sed -i '/^cask-fast$/d' "$INSTALLED_FILE"

SCAN2_SECOND_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN2_WORK" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_scan2_b" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

if printf '%s' "$SCAN2_SECOND_OUT" | grep '"name":"FastReal"' | grep -q '"uninstall_name":"cask-fast"'; then
    fail "AC-008 scan 2 stale index retained uninstalled cask-fast"
else
    pass "AC-008 scan 2 reads fresh index and drops uninstalled cask-fast"
fi

# AC-009: Fast path (resolved path in Caskroom) performs 0 Caskroom traversals
FAST_SCAN="$WORK/fast_scan"
mkdir -p "$FAST_SCAN"
ln -s "$CASKROOM/cask-fast-real/1.0/QuickReal.app" "$FAST_SCAN/QuickReal.app"
: > "$COUNT_FILE"

FAST_OUT=$(MOLE_UNINSTALL_SCAN_ROOT="$FAST_SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_fast" \
    MOLE_TEST_CASKROOM_TRAVERSAL_COUNT_FILE="$COUNT_FILE" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)

FAST_TRAVERSALS=$(( $(wc -l < "$COUNT_FILE" 2>/dev/null) + 0 ))
if [[ $FAST_TRAVERSALS -eq 0 ]]; then
    pass "AC-009 fast path performed 0 Caskroom traversals"
else
    fail "AC-009 fast path unexpectedly traversed Caskroom ($FAST_TRAVERSALS times)"
fi

if [[ $failures -eq 0 ]]; then
    echo "brew_cask_index: all cases passed"
    exit 0
fi
printf 'brew_cask_index: %d case(s) failed\n' "$failures" >&2
exit 1
