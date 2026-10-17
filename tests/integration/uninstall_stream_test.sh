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

# AC-005 & AC-004: Metadata worker blocked -> identity row visible, parent alive, done not emitted.
# Release -> full row + done emitted, parent exits, no surviving workers.
BLOCK_FILE="$WORK/block"
touch "$BLOCK_FILE"
PID_FILE="$WORK/worker_pids"
: > "$PID_FILE"
STREAM_OUT="$WORK/stream_out"
: > "$STREAM_OUT"

MOLE_TEST_METADATA_BLOCK_FILE="$BLOCK_FILE" \
MOLE_TEST_METADATA_PID_FILE="$PID_FILE" \
MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_ac5" \
bash "$UNINSTALL" --list-stream > "$STREAM_OUT" 2> "$WORK/ac5_err" &
AC5_PID=$!

for i in {1..50}; do
    [[ -s "$PID_FILE" ]] && grep -q '{"path":' "$STREAM_OUT" 2> /dev/null && break
    sleep 0.05
done

if grep -q '{"path":' "$STREAM_OUT" 2> /dev/null; then
    pass "AC-005 identity row visible while worker blocked"
else
    fail "AC-005 identity row not visible in time"
fi

if grep -q '"event":"done"' "$STREAM_OUT" 2> /dev/null; then
    fail "AC-005 done marker emitted prematurely while worker blocked"
else
    pass "AC-005 done marker not emitted while worker blocked"
fi

if kill -0 "$AC5_PID" 2> /dev/null; then
    pass "AC-005 parent process remains alive while worker blocked"
else
    fail "AC-005 parent process exited prematurely"
fi

WORKER_PID=$(head -1 "$PID_FILE" 2> /dev/null || true)
if [[ -n "$WORKER_PID" ]] && kill -0 "$WORKER_PID" 2> /dev/null; then
    pass "AC-005 worker process is alive and blocked"
else
    fail "AC-005 worker process not running/recorded"
fi

# Release the worker
rm -f "$BLOCK_FILE"
wait "$AC5_PID" 2> /dev/null || true

if grep -q '"event":"done"' "$STREAM_OUT" 2> /dev/null; then
    pass "AC-005 done marker emitted after worker released"
else
    fail "AC-005 done marker missing after release"
fi

if [[ -n "$WORKER_PID" ]] && kill -0 "$WORKER_PID" 2> /dev/null; then
    fail "AC-005 worker process survived after parent exit"
else
    pass "AC-005 no surviving scanning workers after parent exit"
fi

# AC-006: Cancellation terminates all managed workers; no done emitted
touch "$BLOCK_FILE"
: > "$PID_FILE"
CANCEL_OUT="$WORK/cancel_out"
: > "$CANCEL_OUT"

MOLE_TEST_METADATA_BLOCK_FILE="$BLOCK_FILE" \
MOLE_TEST_METADATA_PID_FILE="$PID_FILE" \
MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_ac6" \
bash "$UNINSTALL" --list-stream > "$CANCEL_OUT" 2> "$WORK/ac6_err" &
AC6_PID=$!

for i in {1..50}; do
    [[ -s "$PID_FILE" ]] && break
    sleep 0.05
done
CANCEL_WORKER_PID=$(head -1 "$PID_FILE" 2> /dev/null || true)

kill -TERM "$AC6_PID" 2> /dev/null || true
wait "$AC6_PID" 2> /dev/null || true
rm -f "$BLOCK_FILE"

if [[ -n "$CANCEL_WORKER_PID" ]] && kill -0 "$CANCEL_WORKER_PID" 2> /dev/null; then
    fail "AC-006 managed worker survived cancellation"
    kill -KILL "$CANCEL_WORKER_PID" 2> /dev/null || true
else
    pass "AC-006 managed workers terminated on cancellation"
fi

if grep -q '"event":"done"' "$CANCEL_OUT" 2> /dev/null; then
    fail "AC-006 done marker emitted on cancellation"
else
    pass "AC-006 no done marker emitted on cancellation"
fi

# AC-007: Non-publishing workers do not hold list pipe
EOF_TEST_SCRIPT="$WORK/eof_test.sh"
cat > "$EOF_TEST_SCRIPT" <<'EOF_SH'
#!/bin/bash
exec 3>&1
(sleep 0.2) 3>&- > /dev/null 2>&1 < /dev/null &
exit 0
EOF_SH
chmod +x "$EOF_TEST_SCRIPT"

EOF_CONTROL_SCRIPT="$WORK/eof_control.sh"
cat > "$EOF_CONTROL_SCRIPT" <<'EOF_SH'
#!/bin/bash
exec 3>&1
(sleep 0.2) > /dev/null 2>&1 < /dev/null &
exit 0
EOF_SH
chmod +x "$EOF_CONTROL_SCRIPT"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
bash "$EOF_TEST_SCRIPT" 3>&1 | cat > /dev/null
END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
DIFF_MS=$((END_MS - START_MS))
if [[ $DIFF_MS -lt 150 ]]; then
    pass "AC-007 closed fd does not delay pipe EOF ($DIFF_MS ms)"
else
    fail "AC-007 closed fd delayed pipe EOF ($DIFF_MS ms)"
fi

CTRL_START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
bash "$EOF_CONTROL_SCRIPT" 3>&1 | cat > /dev/null
CTRL_END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
CTRL_DIFF_MS=$((CTRL_END_MS - CTRL_START_MS))
if [[ $CTRL_DIFF_MS -ge 150 ]]; then
    pass "AC-007 control fixture with retained fd delays EOF ($CTRL_DIFF_MS ms)"
else
    fail "AC-007 control fixture unexpectedly finished early ($CTRL_DIFF_MS ms)"
fi

# AC-008: Unreadable metadata app emits identity and full row with N/A size; fatal error does not return done
UNREADABLE_APP="$SCAN/Unreadable.app/Contents"
mkdir -p "$UNREADABLE_APP"
touch "$UNREADABLE_APP/Info.plist"
chmod 000 "$UNREADABLE_APP/Info.plist"

UNREADABLE_OUT="$(MOLE_UNINSTALL_SCAN_ROOT="$SCAN" \
    MOLE_UNINSTALL_META_CACHE_DIR="$WORK/cache_ac8" \
    bash "$UNINSTALL" --list-stream 2> /dev/null)"

if printf '%s' "$UNREADABLE_OUT" | grep -q '"name":"Unreadable"'; then
    pass "AC-008 unreadable app emitted in list stream"
else
    fail "AC-008 unreadable app missing from list stream"
fi

if printf '%s' "$UNREADABLE_OUT" | grep '"name":"Unreadable"' | grep -q '"size":"N/A"'; then
    pass "AC-008 unreadable app preserves unknown N/A size"
else
    fail "AC-008 unreadable app did not preserve N/A size: $(printf '%s' "$UNREADABLE_OUT" | grep '"name":"Unreadable"')"
fi

chmod 755 "$UNREADABLE_APP/Info.plist"
rm -rf "$SCAN/Unreadable.app"

# Fatal error case: non-existent root
FATAL_OUT="$(MOLE_UNINSTALL_SCAN_ROOT="/non_existent_path_xyz_123" \
    bash "$UNINSTALL" --list-stream 2> /dev/null || true)"
if printf '%s' "$FATAL_OUT" | grep -q '"event":"done"'; then
    fail "AC-008 fatal error unexpectedly emitted done"
else
    pass "AC-008 fatal error does not emit done"
fi

rm -rf "$WORK"

if [[ $failures -eq 0 ]]; then
    echo "uninstall_stream: all cases passed"
    exit 0
fi
printf 'uninstall_stream: %d case(s) failed\n' "$failures" >&2
exit 1
