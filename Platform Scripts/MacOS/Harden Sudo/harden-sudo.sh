#!/bin/bash
###############################################################################
# harden-sudo.sh
#
# WHAT IT DOES
#   Hardens sudo with a drop-in file in /etc/sudoers.d (CIS macOS benchmark):
#     - timestamp_timeout=0  : sudo asks for the password every time, so a
#                              malicious process can't reuse a recent sudo.
#     - timestamp_type=tty   : a sudo ticket is valid only in the terminal
#                              where it was created.
#   /etc/sudoers itself is never edited. Every change is validated with
#   visudo before and after it is installed, and rolled back if invalid.
#
# ACTIONS (in order)
#   1. Root + lock check.
#   2. Checks /etc/sudoers includes /private/etc/sudoers.d (macOS default).
#   3. If the drop-in already has the wanted content: nothing to do.
#   4. Writes the content to a temp file, checks it with 'visudo -cf'.
#   5. Installs it as root:wheel 0440, then checks the full config with
#      'visudo -c'. If that fails, removes the file again (rollback).
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 week (re-applies if removed)
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = hardening in place
#   1 = not root, includedir missing, or validation failed (nothing changed)
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/HardenSudo/HardenSudo.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
# Minutes a sudo ticket stays valid (0 = always ask).
TIMESTAMP_TIMEOUT=0
# tty = ticket per terminal session (CIS recommendation).
TIMESTAMP_TYPE="tty"
# Drop-in file name. sudo ignores names containing '.' or ending in '~'.
DROPIN_FILE="/etc/sudoers.d/10_intune_sudo_hardening"
# ----------------------------------------------------------------------------

TASK_NAME="HardenSudo"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576

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
    rm -f "${TMP_FILE:-}" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
    exit "$1"
}

wanted_content() {
    printf '%s\n' "# Managed by Microsoft Intune (harden-sudo.sh) - do not edit locally."
    printf 'Defaults timestamp_timeout=%s\n' "$TIMESTAMP_TIMEOUT"
    printf 'Defaults timestamp_type=%s\n' "$TIMESTAMP_TYPE"
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

# 2. sudoers must include the drop-in directory.
if ! grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers\.d' /etc/sudoers; then
    finish 1 "FAILED: /etc/sudoers doesn't include /etc/sudoers.d. Not changing /etc/sudoers - fix manually."
fi
mkdir -p /etc/sudoers.d

# 3. Already correct?
if [ -f "$DROPIN_FILE" ] && [ "$(cat "$DROPIN_FILE")" = "$(wanted_content)" ]; then
    finish 0 "OK: sudo hardening already in place ($DROPIN_FILE)."
fi

# 4. Build and validate in a temp file.
TMP_FILE=$(mktemp /tmp/sudo_hardening.XXXXXX) || finish 1 "FAILED: could not create a temp file."
wanted_content > "$TMP_FILE"
if ! visudo -cf "$TMP_FILE" >>"$LOG_FILE" 2>&1; then
    finish 1 "FAILED: new sudoers content didn't pass visudo. Nothing changed."
fi

# 5. Install, then validate the whole configuration.
backup=""
if [ -f "$DROPIN_FILE" ]; then
    backup="${DROPIN_FILE}~intune-backup"   # names ending in '~' are ignored by sudo
    cp -p "$DROPIN_FILE" "$backup"
fi
if ! install -m 0440 -o root -g wheel "$TMP_FILE" "$DROPIN_FILE"; then
    finish 1 "FAILED: could not install $DROPIN_FILE."
fi
if visudo -c >>"$LOG_FILE" 2>&1; then
    rm -f "$backup"
    finish 0 "OK: sudo hardening installed (timeout=$TIMESTAMP_TIMEOUT, type=$TIMESTAMP_TYPE)."
fi

# Rollback.
if [ -n "$backup" ]; then mv -f "$backup" "$DROPIN_FILE"; else rm -f "$DROPIN_FILE"; fi
finish 1 "FAILED: full sudoers check failed after install - change rolled back."
