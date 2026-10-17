#!/bin/bash
# Integration test for the bundled uninstall streaming list (zmole local patch,
# t029). Runs the real uninstall.sh against a fixture scan root and an isolated
# HOME; never touches the developer's applications or config.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNINSTALL="$REPO_ROOT/src/zmole/Resources/mole/bin/uninstall.sh"

failures=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1" >&2
    failures=$((failures + 1))
}

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "${WORK:-}"' EXIT
HOME="$WORK/home"
export HOME
SCAN="$WORK/apps"
mkdir -p "$SCAN/Foo.app/Contents"
cat > "$SCAN/Foo.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.foo</string>
  <key>CFBundleName</key>
  <string>Foo</string>
  <key>CFBundleShortVersionString</key>
  <string>2.3</string>
</dict>
</plist>
PLIST
printf 'payload\n' > "$SCAN/Foo.app/Contents/payload.bin"

OUT="$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache" \
    bash "$UNINSTALL" --list-stream 2> "$WORK/err")"
RC=$?

if [[ $RC -eq 0 ]]; then
    pass "t029 list-stream exits 0"
else
    fail "t029 list-stream rc=$RC stderr=$(head -3 "$WORK/err")"
fi

VERDICT="$(printf '%s' "$OUT" | python3 -c '
import json, sys

lines = [line for line in sys.stdin.read().splitlines() if line.strip()]
rows = []
for line in lines:
    try:
        rows.append(json.loads(line))
    except json.JSONDecodeError:
        print("bad_json:" + line)
        sys.exit(0)

if not rows:
    print("empty")
    sys.exit(0)
if rows[-1].get("event") != "done":
    print("no_done_marker")
    sys.exit(0)
app_rows = rows[:-1]
if not app_rows:
    print("empty")
    sys.exit(0)

first = app_rows[0]
if "size" in first or "bundle_id" in first:
    print("identity_row_not_first")
    sys.exit(0)

full = app_rows[-1]
checks = {
    "path": full.get("path", "").endswith("/Foo.app"),
    "bundle": full.get("bundle_id") == "com.example.foo",
    "uninstall_name": full.get("uninstall_name") == "Foo",
    "version": full.get("version") == "2.3",
    "size_is_string": isinstance(full.get("size"), str),
    "size_not_zero": full.get("size") not in ("0", "", None),
    "last_used_epoch_is_int": isinstance(full.get("last_used_epoch"), int),
}
failed = [name for name, ok in checks.items() if not ok]
print("ok" if not failed else "failed:" + ",".join(failed))
')"

case "$VERDICT" in
    ok*) pass "t029 identity row precedes the versioned full row with done marker" ;;
    *) fail "t029 stream contract: $VERDICT" ;;
esac

if printf '%s' "$OUT" | grep -q '"size": *"N/A (Steam-managed)"'; then
    fail "t029 fixture unexpectedly marked Steam-managed"
else
    pass "t029 plain app is not Steam-managed"
fi

# Named-uninstall confirmation protocol: empty stdin aborts, `y\n` proceeds
# with the dry-run. The fixture app must survive both probes.
if [[ -d "$SCAN/Foo.app/Contents" ]]; then
    pass "fixture app exists before named-uninstall probes"
else
    fail "fixture app missing before named-uninstall probes"
fi

EMPTY_OUT="$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache" \
    bash "$UNINSTALL" Foo --dry-run < /dev/null 2>&1)"
if printf '%s' "$EMPTY_OUT" | grep -q "Aborted."; then
    pass "named uninstall aborts on empty stdin"
else
    fail "named uninstall empty stdin did not abort: $(printf '%s' "$EMPTY_OUT" | tail -2)"
fi
if [[ -d "$SCAN/Foo.app/Contents" ]]; then
    pass "fixture app survives the aborted dry-run"
else
    fail "fixture app disappeared after aborted dry-run"
fi

RESUME_OUT="$(printf 'y\n' | MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache" \
    bash "$UNINSTALL" Foo --dry-run 2>&1)"
if printf '%s' "$RESUME_OUT" | grep -q "Matched"; then
    pass "named uninstall dry-run proceeds with y confirm"
else
    fail "named uninstall y-confirm dry-run did not proceed: $(printf '%s' "$RESUME_OUT" | tail -2)"
fi

rm -rf "$WORK"

if [[ $failures -eq 0 ]]; then
    echo "uninstall_stream: all cases passed"
    exit 0
fi
printf 'uninstall_stream: %d case(s) failed\n' "$failures" >&2
exit 1
