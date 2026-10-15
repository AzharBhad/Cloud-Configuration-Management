#!/bin/bash
###############################################################################
# remove-local-admin-rights.sh
#
# WHAT IT DOES
#   Removes local administrator rights from every user on the Mac except the
#   approved admin accounts (for example the Intune/LAPS-managed local admin).
#   Users stay as standard users; their data, FileVault access (Secure Token)
#   and passwords are not touched.
#
# ACTIONS (in order)
#   1. Checks it runs as root and that no other copy is running (lock).
#   2. Safety check: at least one APPROVED admin account exists, is enabled
#      and is already in the admin group. If not, it stops WITHOUT changes so
#      the Mac is never left without an administrator.
#   3. Reads the members of the local "admin" group.
#   4. For each member that is not approved, not root, not a system account
#      (UID < 501 or name starting with "_"): removes it from the admin group
#      with dseditgroup and checks the result.
#   5. Writes one summary line.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (runs as root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = success (nothing to do, or all unapproved admins removed / dry run)
#   1 = failure (not root, safety check failed, or a removal failed)
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/RemoveLocalAdminRights/RemoveLocalAdminRights.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
# Accounts that KEEP admin rights. Use the short (account) names.
# Replace the placeholder with the local admin account created during
# Automated Device Enrollment (the account Intune manages with LAPS).
APPROVED_ADMINS=("<managed-admin-account>")

# true = only log what would be removed, change nothing (use for a pilot).
DRY_RUN=false

# Accounts with a UID below this are system/service accounts and are skipped.
MIN_USER_UID=501
# ----------------------------------------------------------------------------

TASK_NAME="RemoveLocalAdminRights"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

init_log() {
    mkdir -p "$LOG_DIR"
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

finish() {
    # $1 = exit code, $2 = summary line
    log "$2"
    log "===== End (exit $1) ====="
    echo "$2"
    rmdir "$LOCK_DIR" 2>/dev/null
    exit "$1"
}

# Returns 0 if $1 is in APPROVED_ADMINS.
is_approved() {
    local name="$1" approved
    for approved in ${APPROVED_ADMINS[@]+"${APPROVED_ADMINS[@]}"}; do
        [ "$name" = "$approved" ] && return 0
    done
    return 1
}

# Returns 0 if user $1 exists in the local directory.
user_exists() {
    dscl . -read "/Users/$1" UniqueID >/dev/null 2>&1
}

# Prints the UID of user $1 (empty if unknown).
user_uid() {
    dscl . -read "/Users/$1" UniqueID 2>/dev/null | awk '/UniqueID:/ {print $2}'
}

# Returns 0 if user $1 is (directly or nested) a member of the admin group.
is_admin() {
    dsmemberutil checkmembership -U "$1" -G admin 2>/dev/null | grep -q "is a member"
}

# Returns 0 if user $1 is disabled.
is_disabled() {
    dscl . -read "/Users/$1" AuthenticationAuthority 2>/dev/null | grep -q "DisabledUser"
}

# ------------------------------- MAIN ----------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root. Set 'Run script as signed-in user' to No."
    exit 1
fi

init_log
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another run is in progress (lock $LOCK_DIR). Exiting."
    echo "Another run is in progress."
    exit 0
fi
log "===== Start (DRY_RUN=$DRY_RUN) ====="

# 2. Safety check - an approved, enabled admin must exist before anyone is demoted.
safe_admin=""
for approved in ${APPROVED_ADMINS[@]+"${APPROVED_ADMINS[@]}"}; do
    case "$approved" in "<"*">") continue ;; esac   # skip unreplaced placeholder
    if user_exists "$approved" && is_admin "$approved" && ! is_disabled "$approved"; then
        safe_admin="$approved"
        break
    fi
done
if [ -z "$safe_admin" ]; then
    finish 1 "FAILED: no approved admin account found that exists, is enabled and is an admin. No changes made. Check APPROVED_ADMINS."
fi
log "Safety check passed: approved admin '$safe_admin' is present and enabled."

# 3. Read the admin group members.
members=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/^GroupMembership://')
if [ -z "$members" ]; then
    finish 1 "FAILED: could not read the admin group membership."
fi
log "Admin group members: $members"

removed=0
failed=0
skipped=0
for member in $members; do
    if [ "$member" = "root" ] || is_approved "$member"; then
        log "Keep '$member' (root or approved)."
        skipped=$((skipped + 1))
        continue
    fi
    case "$member" in
        _*) log "Skip '$member' (system account)."; skipped=$((skipped + 1)); continue ;;
    esac
    if ! user_exists "$member"; then
        log "Skip '$member' (not a local user record)."
        skipped=$((skipped + 1))
        continue
    fi
    uid=$(user_uid "$member")
    if [ -z "$uid" ] || [ "$uid" -lt "$MIN_USER_UID" ]; then
        log "Skip '$member' (UID '$uid' below $MIN_USER_UID)."
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: would remove '$member' (UID $uid) from admin."
        removed=$((removed + 1))
        continue
    fi

    if dseditgroup -o edit -d "$member" -t user admin >>"$LOG_FILE" 2>&1 && ! is_admin "$member"; then
        log "Removed '$member' (UID $uid) from admin."
        removed=$((removed + 1))
    else
        log "ERROR: could not remove '$member' from admin."
        failed=$((failed + 1))
    fi
done

summary="Removed=$removed Failed=$failed Kept/Skipped=$skipped DryRun=$DRY_RUN"
if [ "$failed" -gt 0 ]; then
    finish 1 "FAILED: $summary"
fi
finish 0 "OK: $summary"
