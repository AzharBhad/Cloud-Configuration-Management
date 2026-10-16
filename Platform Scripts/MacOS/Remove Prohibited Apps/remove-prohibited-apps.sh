#!/bin/bash
###############################################################################
# remove-prohibited-apps.sh
#
# WHAT IT DOES
#   Finds and removes apps your organization doesn't allow (for example
#   unapproved remote-access tools, P2P/torrent clients, crypto miners) that
#   Intune didn't install and therefore can't uninstall. Stops their
#   processes, unloads and deletes their launchd jobs, and deletes the app
#   bundles. Starts in DRY RUN (report only) - review the log, then set
#   DRY_RUN=false.
#
# ACTIONS (in order)
#   1. Root + lock check.
#   2. launchd jobs: plists in /Library/LaunchDaemons, /Library/LaunchAgents
#      and each user's ~/Library/LaunchAgents whose file name starts with a
#      LAUNCHD_PREFIXES entry -> bootout, then delete the plist.
#   3. Processes: pkill -x for each PROCESS_NAMES entry.
#   4. App bundles: each APP_NAMES entry in /Applications, /Applications/Utilities
#      and each user's ~/Applications -> delete (real .app folders only,
#      never symlinks).
#   5. Summary line.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = nothing found, everything removed, or dry run
#   1 = not root, or something could not be removed
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/RemoveProhibitedApps/RemoveProhibitedApps.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
# EXAMPLES ONLY - replace with your organization's prohibited-software list.
# Remove any entry your organization approves (for example a sanctioned
# remote-support tool).
APP_NAMES=("AnyDesk.app" "TeamViewer.app" "Transmission.app" "qBittorrent.app")
PROCESS_NAMES=("AnyDesk" "TeamViewer" "Transmission" "qbittorrent")
LAUNCHD_PREFIXES=("com.philandro.anydesk" "com.teamviewer." "org.m0k.transmission")

# true = only report what would be removed (default for the pilot).
DRY_RUN=true
# ----------------------------------------------------------------------------

TASK_NAME="RemoveProhibitedApps"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576

found=0
removed=0
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

# Returns 0 if file name $1 starts with one of LAUNCHD_PREFIXES.
matches_prefix() {
    local name="$1" prefix
    for prefix in ${LAUNCHD_PREFIXES[@]+"${LAUNCHD_PREFIXES[@]}"}; do
        case "$name" in "$prefix"*) return 0 ;; esac
    done
    return 1
}

# Unloads and deletes plist $1 in launchd domain $2 (system or gui/<uid>).
remove_launchd_job() {
    local plist="$1" domain="$2" label
    found=$((found + 1))
    label=$(basename "$plist" .plist)
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: would unload $domain/$label and delete $plist"
        return
    fi
    launchctl bootout "$domain/$label" >>"$LOG_FILE" 2>&1
    if rm -f "$plist" && [ ! -e "$plist" ]; then
        log "Removed launchd job $plist"
        removed=$((removed + 1))
    else
        log "ERROR: could not delete $plist"
        failed=$((failed + 1))
    fi
}

# Deletes app bundle $1 (must be a real directory ending in .app).
remove_app() {
    local app="$1"
    found=$((found + 1))
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: would delete $app"
        return
    fi
    if rm -rf "$app" && [ ! -e "$app" ]; then
        log "Deleted $app"
        removed=$((removed + 1))
    else
        log "ERROR: could not delete $app"
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
log "===== Start (DRY_RUN=$DRY_RUN) ====="

# 2. launchd jobs.
for dir in /Library/LaunchDaemons /Library/LaunchAgents; do
    for plist in "$dir"/*.plist; do
        [ -f "$plist" ] || continue
        matches_prefix "$(basename "$plist")" && remove_launchd_job "$plist" "system"
    done
done
for home in /Users/*; do
    [ -d "$home/Library/LaunchAgents" ] || continue
    user=$(basename "$home")
    uid=$(id -u "$user" 2>/dev/null) || continue
    for plist in "$home/Library/LaunchAgents"/*.plist; do
        [ -f "$plist" ] || continue
        matches_prefix "$(basename "$plist")" && remove_launchd_job "$plist" "gui/$uid"
    done
done

# 3. Processes.
for proc in ${PROCESS_NAMES[@]+"${PROCESS_NAMES[@]}"}; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        if [ "$DRY_RUN" = true ]; then
            log "DRY RUN: would stop process $proc"
        else
            pkill -x "$proc" >>"$LOG_FILE" 2>&1 && log "Stopped process $proc"
        fi
    fi
done

# 4. App bundles.
for app_name in ${APP_NAMES[@]+"${APP_NAMES[@]}"}; do
    for parent in /Applications /Applications/Utilities /Users/*/Applications; do
        app="$parent/$app_name"
        if [ -d "$app" ] && [ ! -L "$app" ]; then
            remove_app "$app"
        fi
    done
done

summary="Found=$found Removed=$removed Failed=$failed DryRun=$DRY_RUN"
[ "$failed" -gt 0 ] && finish 1 "FAILED: $summary"
finish 0 "OK: $summary"
