#!/bin/bash
# Integration test for the bundled clean trash routing (zmole local patch, t017).
#
# Sources the bundled mole library and exercises the real deletion sink with
# MOLE_CURRENT_COMMAND=clean inside a temporary HOME and Trash directory. No
# real user file outside the temp root is touched.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOLE_LIB="$REPO_ROOT/src/zmole/Resources/mole/lib"

failures=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Each case runs in its own subshell with an isolated HOME and Trash so a crash
# in one case cannot leak into the next.
run_case() {
    local name="$1"
    local body="$2"
    ( set +e; WORK="$(mktemp -d)"; HOME="$WORK/home"; export HOME; mkdir -p "$HOME"; eval "$body" )
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "$name"
    else
        fail "$name"
    fi
}

common_preamble() {
    cat <<'PRE'
mkdir -p "$HOME/.Trash"
# shellcheck disable=SC1090
source "$MOLE_LIB/core/common.sh" >/dev/null 2>&1 || exit 2
# The bundled library enables `set -e`; cases assert on non-zero exit codes.
set +e
MOLE_CURRENT_COMMAND=clean
export MOLE_CURRENT_COMMAND
PRE
}

# AC-001: a deletable cache file moves to the Trash directory.
run_case "AC-001 clean moves target into Trash" '
'"$(common_preamble)"'
mkdir -p "$HOME/Library/Caches/zmole_fixture"
echo payload > "$HOME/Library/Caches/zmole_fixture/file.bin"
safe_remove "$HOME/Library/Caches/zmole_fixture" true
rc=$?
[[ $rc -eq 0 ]] || { echo "safe_remove rc=$rc"; exit 1; }
[[ -e "$HOME/Library/Caches/zmole_fixture" ]] && { echo "origin still present"; exit 1; }
[[ -e "$HOME/.Trash/zmole_fixture" ]] || { echo "not in Trash"; exit 1; }
'

# AC-002: a failed Trash move keeps the original and reports failure.
run_case "AC-002 failed Trash move keeps original and fails" '
'"$(common_preamble)"'
mkdir -p "$HOME/Library/Caches/zmole_keep"
echo payload > "$HOME/Library/Caches/zmole_keep/file.bin"
# Make the Trash directory unwritable so the move must fail.
chmod 500 "$HOME/.Trash"
safe_remove "$HOME/Library/Caches/zmole_keep" true
rc=$?
chmod 700 "$HOME/.Trash"
[[ $rc -ne 0 ]] || { echo "expected failure rc, got $rc"; exit 1; }
[[ -e "$HOME/Library/Caches/zmole_keep/file.bin" ]] || { echo "original was deleted"; exit 1; }
'

# AC-003: the clean flow must not empty the user's Trash. Runs the real
# `clean_trash` entry point (which used to empty ~/.Trash) and checks a
# pre-existing item survives. Without the patch clean_trash deletes it.
run_case "AC-003 running clean_trash keeps existing Trash contents" '
'"$(common_preamble)"'
# shellcheck disable=SC1090
source "$MOLE_LIB/clean/user.sh" >/dev/null 2>&1 || exit 2
set +e
echo keep-me > "$HOME/.Trash/pre_existing.txt"
DRY_RUN=false
clean_trash
rc=$?
[[ $rc -eq 0 ]] || { echo "clean_trash rc=$rc"; exit 1; }
[[ -e "$HOME/.Trash/pre_existing.txt" ]] || { echo "clean emptied the Trash"; exit 1; }
'

# AC-004: dry-run preview does not list emptying the user Trash.
run_case "AC-004 dry-run does not preview Trash emptying" '
'"$(common_preamble)"'
# shellcheck disable=SC1090
source "$MOLE_LIB/clean/user.sh" >/dev/null 2>&1 || exit 2
set +e
echo keep-me > "$HOME/.Trash/pre_existing.txt"
DRY_RUN=true
clean_trash > "$HOME/trash_preview.txt" 2>&1
rc=$?
[[ $rc -eq 0 ]] || { echo "clean_trash rc=$rc"; exit 1; }
[[ -e "$HOME/.Trash/pre_existing.txt" ]] || { echo "dry-run removed trash item"; exit 1; }
if grep -qi "Trash" "$HOME/trash_preview.txt"; then
    echo "dry-run preview mentioned Trash: $(cat "$HOME/trash_preview.txt")"
    exit 1
fi
'

# AC-005: a target that cannot be trashed is kept and the command fails instead
# of falling back to permanent deletion.
run_case "AC-005 un-trashable target is not permanently deleted" '
'"$(common_preamble)"'
mkdir -p "$HOME/Library/Caches/zmole_priv"
echo payload > "$HOME/Library/Caches/zmole_priv/file.bin"
# Redirect the Trash to an unwritable location so the move must fail.
mkdir -p "$HOME/blocked"
chmod 500 "$HOME/blocked"
MOLE_TRASH_DIR="$HOME/blocked/Trash"
export MOLE_TRASH_DIR
safe_remove "$HOME/Library/Caches/zmole_priv" true
rc=$?
chmod 700 "$HOME/blocked"
[[ $rc -ne 0 ]] || { echo "expected failure rc, got $rc"; exit 1; }
[[ -e "$HOME/Library/Caches/zmole_priv/file.bin" ]] || { echo "original was deleted"; exit 1; }
'

# AC-005 (privileged sink): the sudo deletion path must delegate to the shared
# Trash-move helper and must not permanently delete. The marker proves the
# helper is reached; the un-patched anchor never calls it, so this case fails
# without the patch.
run_case "AC-005 privileged sink delegates to the Trash helper" '
'"$(common_preamble)"'
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_move_path_to_user_trash() { printf "called\n" > "$HOME/used_helper"; return 1; }
mkdir -p "$HOME/Library/Caches/zmole_priv_sink"
echo payload > "$HOME/Library/Caches/zmole_priv_sink/file.bin"
safe_sudo_remove "$HOME/Library/Caches/zmole_priv_sink"
rc=$?
[[ -e "$HOME/used_helper" ]] || { echo "privileged path did not delegate to the Trash helper"; exit 1; }
[[ $rc -ne 0 ]] || { echo "expected failure rc, got $rc"; exit 1; }
[[ -e "$HOME/Library/Caches/zmole_priv_sink/file.bin" ]] || { echo "original was deleted by privileged path"; exit 1; }
'

# Scope: non-clean commands keep permanent deletion.
run_case "non-clean commands still delete permanently" '
mkdir -p "$HOME/.Trash"
# shellcheck disable=SC1090
source "$MOLE_LIB/core/common.sh" >/dev/null 2>&1 || exit 2
set +e
# Use a plain rm function so safe_remove takes its direct-deletion branch
# instead of the timed helper, which needs a controlling terminal.
rm() { command rm "$@"; }
MOLE_CURRENT_COMMAND=optimize
export MOLE_CURRENT_COMMAND
mkdir -p "$HOME/Library/Caches/zmole_opt"
echo payload > "$HOME/Library/Caches/zmole_opt/file.bin"
safe_remove "$HOME/Library/Caches/zmole_opt" true
rc=$?
[[ $rc -eq 0 ]] || { echo "safe_remove rc=$rc"; exit 1; }
[[ -e "$HOME/Library/Caches/zmole_opt" ]] && { echo "optimize target not removed"; exit 1; }
[[ -e "$HOME/.Trash/zmole_opt" ]] && { echo "optimize target was trashed"; exit 1; }
exit 0
'

# Multiple targets with the same basename must all survive in the Trash; the
# suffix scheme must never overwrite an earlier entry.
run_case "AC-001 duplicate basenames do not overwrite each other" '
'"$(common_preamble)"'
for n in one two three; do
    mkdir -p "$HOME/Library/Caches/$n/zmole_dup"
    echo "$n" > "$HOME/Library/Caches/$n/zmole_dup/payload.txt"
done
safe_remove "$HOME/Library/Caches/one/zmole_dup" true
safe_remove "$HOME/Library/Caches/two/zmole_dup" true
safe_remove "$HOME/Library/Caches/three/zmole_dup" true
count=$(command find "$HOME/.Trash" -maxdepth 1 -name "zmole_dup*" | wc -l | tr -d " ")
[[ "$count" -eq 3 ]] || { echo "expected 3 trash entries, got $count"; exit 1; }
for n in one two three; do
    command find "$HOME/.Trash" -maxdepth 2 -name payload.txt -exec grep -l "^$n$" {} + > /dev/null || {
        echo "payload for $n lost"; exit 1;
    }
done
'


if [[ $failures -eq 0 ]]; then
    echo "clean_trash_routing: all cases passed"
    exit 0
fi
printf 'clean_trash_routing: %d case(s) failed\n' "$failures" >&2
exit 1
