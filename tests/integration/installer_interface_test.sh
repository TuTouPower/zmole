#!/bin/bash
# Integration test for the bundled installer non-interactive interface
# (zmole local patch, t022). Runs the real installer.sh as a subprocess against
# a temporary scan root and Trash; never touches the developer's real files.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/src/zmole/Resources/mole/bin/installer.sh"

failures=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1" >&2
    failures=$((failures + 1))
}

setup_fixture() {
    WORK="$(mktemp -d)"
    HOME="$WORK/home"
    export HOME
    SCAN="$HOME/Downloads"
    mkdir -p "$SCAN" "$WORK/trash"
    : > "$SCAN/app.dmg"
    : > "$SCAN/notes.txt"
    # A plain zip with no installer payload.
    local plain="$WORK/plain"
    mkdir -p "$plain"
    printf 'readme\n' > "$plain/readme.txt"
    (cd "$plain" && zip -q -r "$SCAN/plain.zip" readme.txt)
    # A zip that contains an installer payload.
    local payload="$WORK/payload"
    mkdir -p "$payload"
    : > "$payload/Setup.pkg"
    (cd "$payload" && zip -q -r "$SCAN/payload.zip" Setup.pkg)
    export MOLE_INSTALLER_SCAN_ROOT="$SCAN"
    export MOLE_TEST_TRASH_DIR="$WORK/trash"
}

run_installer() {
    MOLE_INSTALLER_SCAN_ROOT="$MOLE_INSTALLER_SCAN_ROOT" \
        MOLE_TEST_TRASH_DIR="$MOLE_TEST_TRASH_DIR" \
        MOLE_INSTALLER_SCAN_DISABLED="${MOLE_INSTALLER_SCAN_DISABLED:-0}" \
        HOME="$HOME" \
        bash "$INSTALLER" "$@"
}

list_metadata() {
    # $1 = output JSON, $2 = suffix; prints size and identity of that entry.
    python3 -c '
import json,sys
data=json.load(sys.stdin)
suffix=sys.argv[1]
for e in data:
    if e["path"].endswith(suffix):
        print(e["size_bytes"]); print(e["identity"]); break
' "$2" <<< "$1"
}

# AC-001 / AC-002: list-json returns candidates with metadata and no TUI.
setup_fixture
LIST_OUTPUT="$(run_installer --list-json 2>"$WORK/list.err")"
STDERR_OUTPUT="$(cat "$WORK/list.err")"
if printf '%s' "$LIST_OUTPUT" | head -c 1 | grep -q '^\['; then
    pass "AC-002 list-json outputs JSON"
else
    fail "AC-002 list-json output: $LIST_OUTPUT"
fi
if printf '%s' "$LIST_OUTPUT$STDERR_OUTPUT" | grep -q $'\033'; then
    fail "AC-002 non-interactive mode emitted terminal escape sequences"
else
    pass "AC-002 no alt-screen/escape output"
fi

PARSED="$(printf '%s' "$LIST_OUTPUT" | python3 -c '
import json,sys
data=json.load(sys.stdin)
print("has_dmg=%s" % any(e["path"].endswith("app.dmg") for e in data))
print("has_plain=%s" % any(e["path"].endswith("plain.zip") for e in data))
print("has_payload=%s" % any(e["path"].endswith("payload.zip") for e in data))
print("fields_ok=%s" % all(e["path"].startswith("/") and isinstance(e["size_bytes"],int) and e["source"] and e["identity"] for e in data))
')"
grep -q "has_dmg=True" <<< "$PARSED" && pass "AC-001 dmg is listed" || fail "AC-001 dmg missing"
grep -q "has_plain=False" <<< "$PARSED" && pass "AC-001 plain zip excluded" || fail "AC-001 plain zip listed"
grep -q "has_payload=True" <<< "$PARSED" && pass "AC-001 installer-payload zip listed" || fail "AC-001 payload zip missing"
grep -q "fields_ok=True" <<< "$PARSED" && pass "AC-002 fields complete" || fail "AC-002 fields incomplete"

DMG_META="$(list_metadata "$LIST_OUTPUT" app.dmg)"
DMG_SIZE="$(sed -n '1p' <<< "$DMG_META")"
DMG_IDENTITY="$(sed -n '2p' <<< "$DMG_META")"
DMG_PATH="$SCAN/app.dmg"

# AC-003: remove a listed path moves it to the Trash.
run_installer --remove "$DMG_PATH" --size "$DMG_SIZE" --identity "$DMG_IDENTITY" >/dev/null 2>&1
RC=$?
if [[ $RC -eq 0 && ! -e "$DMG_PATH" ]] && command find "$MOLE_TEST_TRASH_DIR" -maxdepth 1 -name "app.dmg*" | grep -q .; then
    pass "AC-003 listed path moved to Trash"
else
    fail "AC-003 rc=$RC origin=$([[ -e "$DMG_PATH" ]] && echo present || echo gone) trash=$(ls "$MOLE_TEST_TRASH_DIR" 2>/dev/null)"
fi

# AC-004: not-listed path, missing size/identity, size change and identity
# change are all refused.
setup_fixture
LIST_OUTPUT="$(run_installer --list-json 2>/dev/null)"
DMG_META="$(list_metadata "$LIST_OUTPUT" app.dmg)"
DMG_SIZE="$(sed -n '1p' <<< "$DMG_META")"
DMG_IDENTITY="$(sed -n '2p' <<< "$DMG_META")"
DMG="$SCAN/app.dmg"

# (a) a path that exists in the scan root but is not an installer candidate
run_installer --remove "$SCAN/notes.txt" --size 1 --identity whatever >/dev/null 2>&1
RC_A=$?
# (b) missing verification pair
run_installer --remove "$DMG" >/dev/null 2>&1
RC_B=$?
# (c) size changed after listing (the spec's scenario)
printf 'x' >> "$DMG"
run_installer --remove "$DMG" --size "$DMG_SIZE" --identity "$DMG_IDENTITY" >/dev/null 2>&1
RC_C=$?
SIZE_CHANGE_KEPT=$([[ -s "$DMG" ]] && echo yes || echo no)
# (d) identity mismatch against the listed identity (fresh file, correct size)
: > "$DMG"
CURRENT_SIZE="$(stat -f%z "$DMG" 2>/dev/null || wc -c < "$DMG")"
run_installer --remove "$DMG" --size "$CURRENT_SIZE" --identity "wrong-identity" >/dev/null 2>&1
RC_D=$?

if [[ $RC_A -ne 0 && -e "$SCAN/notes.txt" ]]; then pass "AC-004 path not listed is refused"; else fail "AC-004 unlisted rc=$RC_A"; fi
if [[ $RC_B -ne 0 && -e "$DMG" ]]; then pass "AC-004 missing size/identity is refused"; else fail "AC-004 missing pair rc=$RC_B"; fi
if [[ $RC_C -ne 0 && "$SIZE_CHANGE_KEPT" == "yes" ]]; then pass "AC-004 size change after listing is refused"; else fail "AC-004 size change rc=$RC_C kept=$SIZE_CHANGE_KEPT"; fi
if [[ $RC_D -ne 0 && -e "$DMG" ]]; then pass "AC-004 identity mismatch is refused"; else fail "AC-004 identity rc=$RC_D"; fi

# AC-005: a failed Trash move keeps the original file.
setup_fixture
LIST_OUTPUT="$(run_installer --list-json 2>/dev/null)"
DMG_META="$(list_metadata "$LIST_OUTPUT" app.dmg)"
DMG_SIZE="$(sed -n '1p' <<< "$DMG_META")"
DMG_IDENTITY="$(sed -n '2p' <<< "$DMG_META")"
DMG="$SCAN/app.dmg"
mkdir -p "$WORK/blocked"
chmod 500 "$WORK/blocked"
MOLE_TEST_TRASH_DIR="$WORK/blocked/Trash" run_installer --remove "$DMG" --size "$DMG_SIZE" --identity "$DMG_IDENTITY" >/dev/null 2>&1
RC=$?
chmod 700 "$WORK/blocked"
if [[ $RC -ne 0 && -e "$DMG" ]]; then
    pass "AC-005 failed Trash move keeps the original"
else
    fail "AC-005 rc=$RC origin=$([[ -e "$DMG" ]] && echo present || echo gone)"
fi

# Empty scan must still emit valid JSON on bash 3.2.
setup_fixture
rm -f "$SCAN"/*
EMPTY_OUTPUT="$(run_installer --list-json 2>/dev/null)"
if [[ "$EMPTY_OUTPUT" == "[]" ]]; then
    pass "AC-002 empty scan emits []"
else
    fail "AC-002 empty scan output: '$EMPTY_OUTPUT'"
fi

# t029: removal verifies the target itself and never re-walks the scan roots.
# The scan-disabled hook makes any hidden re-scan fail loudly.
setup_fixture
LIST_OUTPUT="$(run_installer --list-json 2>/dev/null)"
DMG_META="$(list_metadata "$LIST_OUTPUT" app.dmg)"
DMG_SIZE="$(sed -n '1p' <<< "$DMG_META")"
DMG_IDENTITY="$(sed -n '2p' <<< "$DMG_META")"
DMG="$SCAN/app.dmg"
MOLE_INSTALLER_SCAN_DISABLED=1 run_installer --remove "$DMG" --size "$DMG_SIZE" --identity "$DMG_IDENTITY" >/dev/null 2>&1
RC=$?
if [[ $RC -eq 0 && ! -e "$DMG" ]]; then
    pass "t029 removal does not re-scan the roots"
else
    fail "t029 removal rc=$RC origin=$([[ -e "$DMG" ]] && echo present || echo gone)"
fi
MOLE_INSTALLER_SCAN_DISABLED=1 run_installer --remove "$SCAN/notes.txt" --size 1 --identity whatever >/dev/null 2>&1
RC2=$?
if [[ $RC2 -ne 0 && -e "$SCAN/notes.txt" ]]; then
    pass "t029 target verification still refuses non-candidates"
else
    fail "t029 noncandidate rc=$RC2"
fi

if [[ $failures -eq 0 ]]; then
    echo "installer_interface: all cases passed"
    exit 0
fi
printf 'installer_interface: %d case(s) failed\n' "$failures" >&2
exit 1
