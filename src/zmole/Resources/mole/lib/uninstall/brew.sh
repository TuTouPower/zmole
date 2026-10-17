#!/bin/bash
# Mole - Homebrew Cask Uninstallation Support
# Detects Homebrew-managed casks via Caskroom linkage and uninstalls them via brew

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_BREW_UNINSTALL_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_BREW_UNINSTALL_LOADED=1
[[ -n "${MOLE_TIMEOUT_PKG_LIST_SEC:-}" ]] || readonly MOLE_TIMEOUT_PKG_LIST_SEC=10

# Resolve a path to its absolute real path (follows symlinks)
# Args: $1 - path to resolve
# Returns: Absolute resolved path, or empty string on failure
resolve_path() {
    local p="$1"
    [[ -e "$p" ]] || return 1

    # macOS 12.3+ and Linux have realpath
    if realpath "$p" 2> /dev/null; then
        return 0
    fi

    # Fallback: use cd -P to resolve directory, then append basename
    local dir base
    dir=$(cd -P "$(dirname "$p")" 2> /dev/null && pwd) || return 1
    base=$(basename "$p")
    echo "$dir/$base"
}

# Check if Homebrew is installed and accessible
# Returns: 0 if brew is available, 1 otherwise
is_homebrew_available() {
    command -v brew > /dev/null 2>&1
}

# Run a read-only Homebrew probe under a hard deadline. The bash wrapper keeps
# exported test doubles working while production still resolves the real brew
# executable from PATH. More importantly, timeout/signal statuses remain
# distinguishable from a legitimate "not installed" result.
_mole_brew_probe() {
    local duration="$1"
    shift

    if declare -F brew > /dev/null 2>&1; then
        export -f brew
    fi

    HOMEBREW_NO_ENV_HINTS=1 run_with_timeout "$duration" \
        /bin/bash --noprofile --norc -c 'brew "$@"' mole-brew-probe "$@"
}

# Check whether a cask is still recorded as installed in Homebrew.
# Exit codes:
#   0 - cask is installed
#   1 - cask is not installed
#   2 - install state could not be determined
_get_installed_casks_snapshot() {
    if [[ -n "${MOLE_BREW_CASK_INSTALLED_FILE:-}" && -f "${MOLE_BREW_CASK_INSTALLED_FILE}" ]]; then
        cat "${MOLE_BREW_CASK_INSTALLED_FILE}"
        return 0
    fi
    is_homebrew_available || return 1
    local cask_list=""
    local list_rc=0
    cask_list=$(_mole_brew_probe "$MOLE_TIMEOUT_PKG_LIST_SEC" \
        list --cask 2> /dev/null) || list_rc=$?
    [[ $list_rc -eq 124 || $list_rc -ge 128 ]] && return "$list_rc"
    [[ $list_rc -eq 0 ]] || return 2
    printf '%s\n' "$cask_list"
}

is_brew_cask_installed() {
    local cask_name="$1"
    [[ -n "$cask_name" ]] || return 2
    is_homebrew_available || return 2

    if [[ -n "${MOLE_BREW_CASK_LIST_ERROR:-}" && "$MOLE_BREW_CASK_LIST_ERROR" != "0" ]]; then
        return "$MOLE_BREW_CASK_LIST_ERROR"
    fi

    local cask_list=""
    local list_rc=0
    cask_list=$(_get_installed_casks_snapshot) || list_rc=$?
    [[ $list_rc -ne 0 ]] && return "$list_rc"
    grep -qxF "$cask_name" <<< "$cask_list"
}

# Directories searched for Caskroom installations
_get_caskroom_dirs() {
    local -a dirs=()
    local r
    for r in "${HOMEBREW_CASKROOM:-}" "/opt/homebrew/Caskroom" "/usr/local/Caskroom"; do
        [[ -n "$r" && -d "$r" ]] || continue
        dirs+=("$r")
        local canon=""
        canon=$(cd -P "$r" 2> /dev/null && pwd) || true
        if [[ -n "$canon" && "$canon" != "$r" ]]; then
            dirs+=("$canon")
        fi
    done
    printf '%s\n' "${dirs[@]}"
}

# Extract cask token from a Caskroom path
# Args: $1 - path (must be inside Caskroom)
# Prints: cask token to stdout
# Returns: 0 if valid token extracted, 1 otherwise
_extract_cask_token_from_path() {
    local path="$1"
    local room matched=""
    for room in "${HOMEBREW_CASKROOM:-}" "/opt/homebrew/Caskroom" "/usr/local/Caskroom"; do
        [[ -n "$room" && -d "$room" ]] || continue
        if [[ "$path" == "$room/"* ]]; then
            matched="$room"
            break
        fi
        local canon=""
        canon=$(cd -P "$room" 2> /dev/null && pwd) || true
        if [[ -n "$canon" && "$path" == "$canon/"* ]]; then
            matched="$canon"
            break
        fi
    done

    [[ -n "$matched" ]] || return 1

    local rel="${path#"$matched"/}"
    local token="${rel%%/*}"

    # Validate token looks like a valid cask name (lowercase alphanumeric with hyphens)
    if [[ -n "$token" && "$token" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        echo "$token"
        return 0
    fi

    return 1
}

# Stage 1: Deterministic detection via fully resolved path
# Fast, no false positives - follows all symlinks.
# Zero Caskroom traversals required (AC-009).
_detect_cask_via_resolved_path() {
    local app_path="$1"
    local resolved
    if resolved=$(resolve_path "$app_path") && [[ -n "$resolved" ]]; then
        [[ "$(basename "$resolved")" == "$(basename "$app_path")" ]] || return 1
        local token
        if token=$(_extract_cask_token_from_path "$resolved"); then
            # Verify the token is in the installed snapshot (AC-009)
            local installed_rc=0
            is_brew_cask_installed "$token" || installed_rc=$?
            if [[ $installed_rc -eq 0 ]]; then
                echo "$token"
                return 0
            fi
            [[ $installed_rc -gt 1 ]] && return "$installed_rc"
            return 1
        fi
    fi
    return 1
}

# Build Caskroom index once per scan session (AC-001)
_ensure_caskroom_index() {
    is_homebrew_available || return 1
    local index_target="${MOLE_BREW_CASK_INDEX_FILE:-}"
    if [[ -z "$index_target" ]]; then
        index_target=$(create_temp_file) || return 1
        export MOLE_BREW_CASK_INDEX_FILE="$index_target"
    fi

    if [[ -f "${index_target}.ready" ]]; then
        return 0
    fi

    if [[ -n "${MOLE_TEST_CASKROOM_TRAVERSAL_COUNT_FILE:-}" ]]; then
        printf '1\n' >> "$MOLE_TEST_CASKROOM_TRAVERSAL_COUNT_FILE"
    fi

    local room
    while IFS= read -r room; do
        [[ -n "$room" && -d "$room" ]] || continue
        local scan_file=""
        scan_file=$(create_temp_file) || continue
        find "$room" -maxdepth 4 -name "*.app" < /dev/null 2> /dev/null > "$scan_file" || true
        while IFS= read -r match; do
            [[ -n "$match" ]] || continue
            local token
            token=$(_extract_cask_token_from_path "$match" 2> /dev/null) || continue
            local bname
            bname=$(basename "$match")
            printf '%s|%s|%s\n' "$token" "$bname" "$match" >> "$index_target"
        done < "$scan_file"
        rm -f -- "$scan_file" 2> /dev/null || true
    done < <(_get_caskroom_dirs)

    touch "${index_target}.ready"
    return 0
}

# Search Caskroom from shared index
_detect_cask_from_scan_index() {
    local app_bundle_name="$1"
    local app_path="${2:-}"
    [[ -z "$app_bundle_name" ]] && return 1

    local index_rc=0
    _ensure_caskroom_index || index_rc=$?
    [[ $index_rc -ne 0 ]] && return "$index_rc"

    local index_target="${MOLE_BREW_CASK_INDEX_FILE:-}"
    [[ -f "$index_target" ]] || return 1

    if [[ -n "${MOLE_BREW_CASK_LIST_ERROR:-}" && "$MOLE_BREW_CASK_LIST_ERROR" != "0" ]]; then
        return "$MOLE_BREW_CASK_LIST_ERROR"
    fi

    # Pass 1: exact file identity or realpath match (-ef)
    local token bname match
    if [[ -n "$app_path" && -e "$app_path" ]]; then
        local -a identity_tokens=()
        while IFS='|' read -r token bname match; do
            [[ -n "$token" && -n "$match" ]] || continue
            if [[ -e "$match" ]] && [[ "$app_path" -ef "$match" || "$(resolve_path "$app_path" 2>/dev/null)" == "$(resolve_path "$match" 2>/dev/null)" ]]; then
                if is_brew_cask_installed "$token"; then
                    identity_tokens+=("$token")
                fi
            fi
        done < "$index_target"

        local -a uniq_id=()
        for t in "${identity_tokens[@]+"${identity_tokens[@]}"}"; do
            local seen=0
            for u in "${uniq_id[@]+"${uniq_id[@]}"}"; do
                [[ "$t" == "$u" ]] && seen=1 && break
            done
            [[ $seen -eq 0 ]] && uniq_id+=("$t")
        done

        if [[ ${#uniq_id[@]} -eq 1 ]]; then
            # AC-002: Exact file identity confirmed; return without calling brew info!
            echo "${uniq_id[0]}"
            return 0
        fi
    fi

    # Pass 2: Name-based candidates
    local -a name_candidates=()
    while IFS='|' read -r token bname match; do
        [[ -n "$token" && "$bname" == "$app_bundle_name" ]] || continue
        if is_brew_cask_installed "$token"; then
            name_candidates+=("$token")
        fi
    done < "$index_target"

    local -a uniq_candidates=()
    for t in "${name_candidates[@]+"${name_candidates[@]}"}"; do
        local seen=0
        for u in "${uniq_candidates[@]+"${uniq_candidates[@]}"}"; do
            [[ "$t" == "$u" ]] && seen=1 && break
        done
        [[ $seen -eq 0 ]] && uniq_candidates+=("$t")
    done

    ((${#uniq_candidates[@]} > 0)) || return 1

    # Directional probe via brew info for candidate tokens (AC-003, AC-006)
    local -a verified_tokens=()
    for cand in "${uniq_candidates[@]}"; do
        local info_out=""
        local info_rc=0
        info_out=$(_mole_brew_probe "$MOLE_TIMEOUT_PKG_LIST_SEC" info --cask "$cand" 2> /dev/null) || info_rc=$?
        [[ $info_rc -eq 124 || $info_rc -ge 128 ]] && return "$info_rc"
        if [[ $info_rc -eq 0 ]]; then
            if [[ -n "$app_path" ]]; then
                if grep -qF "$app_path" <<< "$info_out"; then
                    verified_tokens+=("$cand")
                elif [[ "$app_path" == "/Applications/$app_bundle_name" ]] && grep -qF "$app_bundle_name" <<< "$info_out"; then
                    verified_tokens+=("$cand")
                fi
            fi
        fi
    done

    if [[ ${#verified_tokens[@]} -eq 1 ]]; then
        echo "${verified_tokens[0]}"
        return 0
    fi

    return 1
}

# Stage 3: Check if app_path is a direct symlink to Caskroom
_detect_cask_via_symlink_check() {
    local app_path="$1"
    [[ -L "$app_path" ]] || return 1

    local target
    target=$(readlink "$app_path" 2> /dev/null) || return 1
    [[ "$(basename "$target")" == "$(basename "$app_path")" ]] || return 1
    local token
    if token=$(_extract_cask_token_from_path "$target"); then
        if is_brew_cask_installed "$token"; then
            echo "$token"
            return 0
        fi
    fi
    return 1
}

# Lifecycle helpers for the per-scan Homebrew cask index (t054)
_init_brew_cask_scan_index() {
    is_homebrew_available || return 0
    if [[ -z "${MOLE_BREW_CASK_INSTALLED_FILE:-}" ]]; then
        local installed_file=""
        installed_file=$(create_temp_file) || return 1
        local list_rc=0
        _mole_brew_probe "$MOLE_TIMEOUT_PKG_LIST_SEC" list --cask 2> /dev/null > "$installed_file" || list_rc=$?
        if [[ $list_rc -eq 0 ]]; then
            export MOLE_BREW_CASK_INSTALLED_FILE="$installed_file"
        elif [[ $list_rc -eq 124 || $list_rc -ge 128 ]]; then
            export MOLE_BREW_CASK_LIST_ERROR="$list_rc"
        else
            export MOLE_BREW_CASK_LIST_ERROR=2
        fi
    fi
    if [[ -z "${MOLE_BREW_CASK_INDEX_FILE:-}" ]]; then
        local index_file=""
        index_file=$(create_temp_file) || return 1
        export MOLE_BREW_CASK_INDEX_FILE="$index_file"
    fi
}

_cleanup_brew_cask_scan_index() {
    if [[ -n "${MOLE_BREW_CASK_INSTALLED_FILE:-}" ]]; then
        rm -f -- "${MOLE_BREW_CASK_INSTALLED_FILE}" 2> /dev/null || true
        unset MOLE_BREW_CASK_INSTALLED_FILE
    fi
    if [[ -n "${MOLE_BREW_CASK_INDEX_FILE:-}" ]]; then
        rm -f -- "${MOLE_BREW_CASK_INDEX_FILE}" "${MOLE_BREW_CASK_INDEX_FILE}.ready" 2> /dev/null || true
        unset MOLE_BREW_CASK_INDEX_FILE
    fi
    unset MOLE_BREW_CASK_LIST_ERROR
}

# Get Homebrew cask name for an app
# Uses multi-stage detection (fast to slow, deterministic to heuristic):
#   1. Resolve symlinks fully, check if path is in Caskroom (fast, deterministic)
#   2. Caskroom shared index (exact identity match, then name-based candidates with brew info)
#   3. Check if app is a direct symlink to Caskroom
#
# Args: $1 - app_path
# Prints: cask token to stdout if brew-managed
# Returns: 0 if Homebrew-managed, 1 otherwise
get_brew_cask_name() {
    local app_path="$1"
    [[ -z "$app_path" || ! -e "$app_path" ]] && return 1
    is_homebrew_available || return 1

    local app_bundle_name
    app_bundle_name=$(basename "$app_path")

    # Try each detection method in order:
    local detect_rc=0
    _detect_cask_via_resolved_path "$app_path" || detect_rc=$?
    [[ $detect_rc -eq 0 ]] && return 0
    [[ $detect_rc -eq 1 ]] || return "$detect_rc"

    detect_rc=0
    _detect_cask_from_scan_index "$app_bundle_name" "$app_path" || detect_rc=$?
    [[ $detect_rc -eq 0 ]] && return 0
    [[ $detect_rc -eq 1 ]] || return "$detect_rc"

    detect_rc=0
    _detect_cask_via_symlink_check "$app_path" || detect_rc=$?
    [[ $detect_rc -eq 0 ]] && return 0
    [[ $detect_rc -eq 1 ]] || return "$detect_rc"

    return 1
}

# Uninstall a Homebrew cask and verify removal
# Args: $1 - cask_name, $2 - app_path (optional, for verification),
#       $3 - zap mode: "nozap" runs a plain uninstall without --zap. Used when
#            another install shares the cask's bundle id: zap stanzas delete
#            bundle-id-keyed prefs/caches that the surviving install still
#            uses (iterm2 and iterm2-beta both zap com.googlecode.iterm2).
# Returns: 0 on success, 1 on ordinary failure, 124 on timeout, or the
# original signal-style status when the operation is interrupted.
brew_uninstall_cask() {
    local cask_name="$1"
    local app_path="${2:-}"
    local zap_mode="${3:-zap}"

    local -a uninstall_args=(uninstall --cask)
    if [[ "$zap_mode" != "nozap" ]]; then
        uninstall_args+=(--zap)
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        debug_log "[DRY RUN] Would brew ${uninstall_args[*]} $cask_name"
        return 0
    fi

    is_homebrew_available || return 1
    [[ -z "$cask_name" ]] && return 1

    debug_log "Attempting brew ${uninstall_args[*]} $cask_name"

    local uninstall_ok=false
    local brew_exit=0

    # Calculate timeout based on app size (large apps need more time)
    local timeout=300 # Default 5 minutes
    if [[ -n "$app_path" && -d "$app_path" ]]; then
        local size_kb=0
        local size_rc=0
        size_kb=$(get_path_size_kb "$app_path") || size_rc=$?
        [[ $size_rc -eq 124 || $size_rc -ge 128 ]] && return "$size_rc"
        [[ $size_rc -eq 0 && "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
        local size_gb=$((size_kb / 1048576))
        if [[ $size_gb -gt 15 ]]; then
            timeout=900 # 15 minutes for very large apps (Xcode, Adobe, etc.)
        elif [[ $size_gb -gt 5 ]]; then
            timeout=600 # 10 minutes for large apps
        fi
        debug_log "App size: ${size_gb}GB, timeout: ${timeout}s"
    fi

    # Run with timeout to prevent hangs from problematic cask scripts.
    if [[ -n "${SUDO_USER:-}" ]]; then
        if run_with_timeout "$timeout" sudo -u "$SUDO_USER" env \
            HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 NONINTERACTIVE=1 \
            brew "${uninstall_args[@]}" "$cask_name" 2>&1; then
            uninstall_ok=true
        else
            brew_exit=$?
        fi
    elif HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 NONINTERACTIVE=1 \
        run_with_timeout "$timeout" brew "${uninstall_args[@]}" "$cask_name" 2>&1; then
        uninstall_ok=true
    else
        brew_exit=$?
    fi

    if [[ "$uninstall_ok" != "true" ]]; then
        debug_log "brew uninstall timeout or failed with exit code: $brew_exit"
        # Timeout and signal statuses are cancellation, not evidence that a
        # partially completed cask action can safely fall back to direct app
        # deletion. Preserve them before any verification.
        if [[ $brew_exit -eq 124 ]]; then
            debug_log "brew uninstall timed out after ${timeout}s, returning failure"
            return 124
        elif [[ $brew_exit -ge 128 ]]; then
            return "$brew_exit"
        fi
    fi

    # Verify removal (only if not timed out)
    local cask_gone=true app_gone=true
    local cask_state=0
    if is_brew_cask_installed "$cask_name"; then
        cask_gone=false
    else
        cask_state=$?
        [[ $cask_state -ge 128 ]] && return "$cask_state"
        [[ $cask_state -eq 1 ]] || cask_gone=false
    fi
    [[ -n "$app_path" && -e "$app_path" ]] && app_gone=false

    # Success: uninstall worked and both are gone, or already uninstalled
    if $cask_gone && $app_gone; then
        debug_log "Successfully uninstalled cask '$cask_name'"
        return 0
    fi

    debug_log "brew uninstall failed: cask_gone=$cask_gone app_gone=$app_gone"
    return 1
}
