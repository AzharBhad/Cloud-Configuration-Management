#!/bin/bash
###############################################################################
# repair-defender-health.sh
#
# WHAT IT DOES
#   Checks Microsoft Defender for Endpoint on the Mac (mdatp health) and
#   fixes what a script can fix: updates security intelligence and turns
#   real-time protection back on when it isn't managed by policy. Problems a
#   script can't fix (not onboarded, no Full Disk Access, extensions not
#   approved) are reported so the device shows as Failed in Intune.
#
# ACTIONS (in order)
#   1. Root + lock check; stops if mdatp isn't installed.
#   2. Reads: healthy, health_issues, licensed, org_id,
#      real_time_protection_enabled, real_time_protection_available,
#      full_disk_access_enabled, tamper_protection.
#   3. Updates security intelligence (mdatp definitions update, with timeout).
#   4. If real-time protection is off: tries
#      'mdatp config real-time-protection --value enabled' (works only when
#      the setting isn't managed by policy / tamper protection).
#   5. Reads health again and reports what is still wrong.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = Defender healthy (after repair if needed)
#   1 = not root, Defender missing, or still unhealthy
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/RepairDefenderHealth/RepairDefenderHealth.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
MDATP="/usr/local/bin/mdatp"
# Seconds to wait for 'mdatp definitions update' before giving up.
DEFINITIONS_TIMEOUT=600
# true = also try to turn real-time protection on when it's off.
REPAIR_REAL_TIME_PROTECTION=true
# true = report "not onboarded to Defender for Endpoint (EDR)" as a failure.
REQUIRE_EDR_ONBOARDING=true
# ----------------------------------------------------------------------------

TASK_NAME="RepairDefenderHealth"
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
    rmdir "$LOCK_DIR" 2>/dev/null
    exit "$1"
}

# Prints the value of one mdatp health field (quotes and spaces removed).
field() {
    "$MDATP" health --field "$1" 2>/dev/null | head -n 1 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Runs "$@" and kills it after $1 seconds. Returns the command's exit code, 124 on timeout.
run_with_timeout() {
    local limit="$1"; shift
    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null
            return 124
        fi
        sleep 5; waited=$((waited + 5))
    done
    wait "$pid"
}

collect_problems() {
    problems=""
    [ "$(field healthy)" = "true" ] || problems="${problems}healthy=false; "
    [ "$(field real_time_protection_enabled)" = "true" ] || problems="${problems}RTP off; "
    [ "$(field real_time_protection_available)" = "false" ] && problems="${problems}RTP unavailable (system extension?); "
    [ "$(field full_disk_access_enabled)" = "false" ] && problems="${problems}no Full Disk Access (PPPC profile); "
    [ "$(field licensed)" = "true" ] || problems="${problems}not licensed/onboarded; "
    if [ "$REQUIRE_EDR_ONBOARDING" = true ]; then
        case "$(field org_id)" in ""|unavailable) problems="${problems}EDR not onboarded (onboarding profile); " ;; esac
    fi
    issues=$(field health_issues)
    case "$issues" in ""|"[]") ;; *) problems="${problems}issues=${issues}; " ;; esac
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

if [ ! -x "$MDATP" ]; then
    finish 1 "FAILED: Microsoft Defender for Endpoint (mdatp) is not installed."
fi

collect_problems
log "Before repair: ${problems:-none} (tamper_protection=$(field tamper_protection))"

# 3. Update security intelligence.
run_with_timeout "$DEFINITIONS_TIMEOUT" "$MDATP" definitions update
rc=$?
if [ "$rc" -eq 0 ]; then log "Security intelligence updated."
elif [ "$rc" -eq 124 ]; then log "WARNING: definitions update timed out after ${DEFINITIONS_TIMEOUT}s."
else log "WARNING: definitions update returned $rc."
fi

# 4. Real-time protection.
if [ "$REPAIR_REAL_TIME_PROTECTION" = true ] && [ "$(field real_time_protection_enabled)" != "true" ]; then
    if "$MDATP" config real-time-protection --value enabled >>"$LOG_FILE" 2>&1; then
        log "Real-time protection turned on."
    else
        log "WARNING: could not turn on real-time protection (managed by policy or tamper protection). Fix the Defender preferences policy."
    fi
fi

# 5. Re-check.
collect_problems
if [ -n "$problems" ]; then
    finish 1 "FAILED: Defender unhealthy - ${problems}"
fi
finish 0 "OK: Defender healthy, RTP on, onboarded ($(field app_version))"
