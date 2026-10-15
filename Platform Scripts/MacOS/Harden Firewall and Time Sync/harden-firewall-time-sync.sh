#!/bin/bash
###############################################################################
# harden-firewall-time-sync.sh
#
# WHAT IT DOES
#   Fills two gaps next to your macOS firewall configuration profile:
#     Firewall (Application Firewall):
#       - logging on
#       - stealth mode on (no reply to pings / port probes)
#       - built-in and downloaded signed apps are NOT automatically allowed
#     Time:
#       - network time on, using the corporate NTP server
#   Accurate time is needed for Kerberos, certificates, Platform SSO and logs.
#
#   NOTE: when the firewall is managed by a configuration profile, macOS
#   blocks command-line changes. The script then logs "managed by profile"
#   for those settings and does NOT fail - set them in the profile instead
#   (Firewall payload: EnableLogging, EnableStealthMode, AllowSigned,
#   AllowSignedApp).
#
# ACTIONS (in order) - each one is skipped when already in the wanted state
#   1. Root + lock check.
#   2. socketfilterfw --setloggingmode on
#   3. socketfilterfw --setstealthmode on
#   4. socketfilterfw --setallowsigned off / --setallowsignedapp off
#   5. systemsetup -setusingnetworktime on and -setnetworktimeserver <NTP_SERVER>
#   6. Summary line.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = all settings applied, already set, or managed by a profile
#   1 = not root, or a setting could not be applied
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/HardenFirewallTimeSync/HardenFirewallTimeSync.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
ENABLE_FIREWALL_LOGGING=true
ENABLE_STEALTH_MODE=true
BLOCK_AUTO_ALLOW_SIGNED=true
CONFIGURE_TIME_SYNC=true
# Corporate NTP server (use your domain controllers or an internal NTP source
# if you have one).
NTP_SERVER="time.apple.com"
# ----------------------------------------------------------------------------

TASK_NAME="HardenFirewallTimeSync"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"

changed=0
failed=0
managed=0

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

# Runs a socketfilterfw "set" command ($2...) when check command output ($1)
# doesn't already contain the wanted text ($3). $4 = friendly name.
fw_setting() {
    local get_flag="$1" set_args="$2" wanted="$3" name="$4" output
    if "$FW" "$get_flag" 2>&1 | grep -Eqi "$wanted"; then
        log "$name: already set."
        return
    fi
    # shellcheck disable=SC2086  # set_args holds two words on purpose
    output=$("$FW" $set_args 2>&1)
    echo "$output" >> "$LOG_FILE"
    if echo "$output" | grep -qi "managed"; then
        log "$name: firewall is managed by a configuration profile - set it in the profile."
        managed=$((managed + 1))
    elif "$FW" "$get_flag" 2>&1 | grep -Eqi "$wanted"; then
        log "$name: set."
        changed=$((changed + 1))
    else
        log "ERROR: $name: could not be set."
        failed=$((failed + 1))
    fi
}

configure_time() {
    local current server
    current=$(systemsetup -getusingnetworktime 2>&1)
    if ! echo "$current" | grep -q "Network Time: On"; then
        systemsetup -setusingnetworktime on >>"$LOG_FILE" 2>&1
        if systemsetup -getusingnetworktime 2>&1 | grep -q "Network Time: On"; then
            log "Network time: turned on."; changed=$((changed + 1))
        else
            log "ERROR: Network time: could not be turned on (Full Disk Access for the Intune agent?)."
            failed=$((failed + 1))
        fi
    else
        log "Network time: already on."
    fi

    server=$(systemsetup -getnetworktimeserver 2>&1 | awk -F': ' '{print $2}')
    if [ "$server" = "$NTP_SERVER" ]; then
        log "Network time server: already $NTP_SERVER."
        return
    fi
    systemsetup -setnetworktimeserver "$NTP_SERVER" >>"$LOG_FILE" 2>&1
    server=$(systemsetup -getnetworktimeserver 2>&1 | awk -F': ' '{print $2}')
    if [ "$server" = "$NTP_SERVER" ]; then
        log "Network time server: set to $NTP_SERVER."; changed=$((changed + 1))
    else
        log "ERROR: Network time server: still '$server'."
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

if [ -x "$FW" ]; then
    [ "$ENABLE_FIREWALL_LOGGING" = true ] && fw_setting --getloggingmode "--setloggingmode on" "Log mode is on" "Firewall logging"
    [ "$ENABLE_STEALTH_MODE" = true ]     && fw_setting --getstealthmode "--setstealthmode on" "stealth mode is on|Stealth mode enabled" "Stealth mode"
    if [ "$BLOCK_AUTO_ALLOW_SIGNED" = true ]; then
        fw_setting --getallowsigned "--setallowsigned off" "built-in signed software DISABLED" "Auto-allow built-in signed software"
        fw_setting --getallowsigned "--setallowsignedapp off" "downloaded signed software DISABLED" "Auto-allow downloaded signed software"
    fi
else
    log "ERROR: socketfilterfw not found."
    failed=$((failed + 1))
fi

[ "$CONFIGURE_TIME_SYNC" = true ] && configure_time

summary="Changed=$changed ManagedByProfile=$managed Failed=$failed"
[ "$failed" -gt 0 ] && finish 1 "FAILED: $summary"
finish 0 "OK: $summary"
