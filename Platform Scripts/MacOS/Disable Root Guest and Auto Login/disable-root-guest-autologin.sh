#!/bin/bash
###############################################################################
# disable-root-guest-autologin.sh
#
# WHAT IT DOES
#   Closes local-access gaps that come back after migrations, manual support
#   or old images:
#     - Root user enabled (has a password)      -> disabled
#     - Guest account / guest access to shares  -> off, leftover home folder removed
#     - Automatic login configured              -> removed, saved password deleted
#
# ACTIONS (in order) - each one is skipped when already in the wanted state
#   1. Root + lock check.
#   2. Root user: if /Users/root has an AuthenticationAuthority (= a password
#      is set), delete it and set the password field to '*' (disabled).
#   3. Guest: if GuestEnabled or a Guest user exists -> 'sysadminctl
#      -guestAccount off'; 'sysadminctl -smbGuestAccess off'; remove a
#      leftover /Users/Guest folder only when no Guest user exists.
#   4. Automatic login: delete loginwindow 'autoLoginUser' and /etc/kcpassword.
#   5. Summary line.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = all items in the wanted state
#   1 = not root, or an item could not be fixed
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/DisableRootGuestAutoLogin/DisableRootGuestAutoLogin.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
DISABLE_ROOT=true
DISABLE_GUEST=true
DISABLE_AUTO_LOGIN=true
# ----------------------------------------------------------------------------

TASK_NAME="DisableRootGuestAutoLogin"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576
LOGINWINDOW="/Library/Preferences/com.apple.loginwindow"

changed=0
failed=0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

init_log() {
    mkdir -p "$LOG_DIR"
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

finish() {
    log "$2"; log "===== End (exit $1) ====="
    echo "$2"
    rmdir "$LOCK_DIR" 2>/dev/null
    exit "$1"
}

root_enabled() {
    dscl . -read /Users/root AuthenticationAuthority >/dev/null 2>&1
}

guest_enabled() {
    [ "$(defaults read "$LOGINWINDOW" GuestEnabled 2>/dev/null)" = "1" ] || dscl . -read /Users/Guest >/dev/null 2>&1
}

disable_root() {
    if ! root_enabled; then
        log "Root user: already disabled."
        return
    fi
    dscl . -delete /Users/root AuthenticationAuthority >>"$LOG_FILE" 2>&1
    dscl . -create /Users/root Password '*' >>"$LOG_FILE" 2>&1
    if root_enabled; then
        log "ERROR: Root user: could not be disabled."
        failed=$((failed + 1))
    else
        log "Root user: disabled."
        changed=$((changed + 1))
    fi
}

disable_guest() {
    if guest_enabled; then
        sysadminctl -guestAccount off >>"$LOG_FILE" 2>&1
        defaults write "$LOGINWINDOW" GuestEnabled -bool false >>"$LOG_FILE" 2>&1
        if guest_enabled; then
            log "ERROR: Guest account: could not be turned off."
            failed=$((failed + 1))
        else
            log "Guest account: turned off."
            changed=$((changed + 1))
        fi
    else
        log "Guest account: already off."
    fi
    sysadminctl -smbGuestAccess off >>"$LOG_FILE" 2>&1 && log "Guest access to shared folders: off."
    if [ -d /Users/Guest ] && ! dscl . -read /Users/Guest >/dev/null 2>&1; then
        rm -rf /Users/Guest && log "Removed leftover /Users/Guest folder." && changed=$((changed + 1))
    fi
}

disable_auto_login() {
    local user
    user=$(defaults read "$LOGINWINDOW" autoLoginUser 2>/dev/null)
    if [ -z "$user" ] && [ ! -f /etc/kcpassword ]; then
        log "Automatic login: already off."
        return
    fi
    [ -n "$user" ] && defaults delete "$LOGINWINDOW" autoLoginUser >>"$LOG_FILE" 2>&1
    rm -f /etc/kcpassword
    if [ -z "$(defaults read "$LOGINWINDOW" autoLoginUser 2>/dev/null)" ] && [ ! -f /etc/kcpassword ]; then
        log "Automatic login: removed."
        changed=$((changed + 1))
    else
        log "ERROR: Automatic login: could not be removed."
        failed=$((failed + 1))
    fi
}

# ------------------------------- MAIN ----------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root. Set 'Run script as signed-in user' to No."
    exit 1
fi
init_log
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another run is in progress. Exiting."; echo "Another run is in progress."; exit 0
fi
log "===== Start ====="

[ "$DISABLE_ROOT" = true ]       && disable_root
[ "$DISABLE_GUEST" = true ]      && disable_guest
[ "$DISABLE_AUTO_LOGIN" = true ] && disable_auto_login

summary="Changed=$changed Failed=$failed"
[ "$failed" -gt 0 ] && finish 1 "FAILED: $summary"
finish 0 "OK: $summary"
