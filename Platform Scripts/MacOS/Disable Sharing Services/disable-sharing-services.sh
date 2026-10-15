#!/bin/bash
###############################################################################
# disable-sharing-services.sh
#
# WHAT IT DOES
#   Turns off macOS sharing and remote-access services that open the Mac to
#   the network: Remote Login (SSH), Screen Sharing, Remote Management (ARD),
#   File Sharing (SMB), Remote Apple Events, Printer Sharing, Internet Sharing
#   and Bluetooth Sharing. Each service can be kept on with a setting below.
#
# ACTIONS (in order) - each one is skipped when already off
#   1. Root + lock check.
#   2. Remote Login ........... launchctl disable + bootout system/com.openssh.sshd
#   3. Screen Sharing ......... launchctl disable + bootout system/com.apple.screensharing
#   4. Remote Management ...... ARD kickstart -deactivate -stop
#   5. File Sharing (SMB) ..... launchctl disable + bootout system/com.apple.smbd
#   6. Remote Apple Events .... launchctl disable + bootout system/com.apple.AEServer
#   7. Printer Sharing ........ cupsctl --no-share-printers
#   8. Internet Sharing ....... com.apple.nat Enabled=0 + bootout system/com.apple.InternetSharing
#   9. Bluetooth Sharing ...... per signed-in user: PrefKeyServicesEnabled=false
#  10. Summary line.
#   launchctl is used instead of systemsetup so no Full Disk Access is needed.
#
# INTUNE SETTINGS
#   Run script as signed-in user ........ No (root - required)
#   Hide script notifications on devices  Yes
#   Script frequency .................... Every 1 day
#   Max number of times to retry ........ 3
#
# EXIT CODES
#   0 = every selected service is off
#   1 = not root, or at least one service could not be turned off
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/DisableSharingServices/DisableSharingServices.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
# true = turn the service off, false = leave it as it is.
DISABLE_REMOTE_LOGIN=true          # SSH
DISABLE_SCREEN_SHARING=true
DISABLE_REMOTE_MANAGEMENT=true     # Apple Remote Desktop agent
DISABLE_FILE_SHARING=true          # SMB
DISABLE_REMOTE_APPLE_EVENTS=true
DISABLE_PRINTER_SHARING=true
DISABLE_INTERNET_SHARING=true
DISABLE_BLUETOOTH_SHARING=true
# ----------------------------------------------------------------------------

TASK_NAME="DisableSharingServices"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
LOCK_DIR="/tmp/${TASK_NAME}.lock"
MAX_LOG_BYTES=1048576
ARD_KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
NAT_PLIST="/Library/Preferences/SystemConfiguration/com.apple.nat"

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

# Returns 0 if the launchd service $1 is already disabled in the system domain.
service_is_disabled() {
    launchctl print-disabled system 2>/dev/null | grep -Eq "\"$1\" => (disabled|true)"
}

# Returns 0 if the launchd service $1 is currently loaded.
service_is_loaded() {
    launchctl print "system/$1" >/dev/null 2>&1
}

# Disables and stops launchd service $1 (friendly name $2).
disable_service() {
    local label="$1" name="$2"
    if service_is_disabled "$label" && ! service_is_loaded "$label"; then
        log "$name: already off."
        return
    fi
    launchctl disable "system/$label" >>"$LOG_FILE" 2>&1
    if service_is_loaded "$label"; then
        launchctl bootout "system/$label" >>"$LOG_FILE" 2>&1
    fi
    if service_is_disabled "$label" && ! service_is_loaded "$label"; then
        log "$name: turned off."
        changed=$((changed + 1))
    else
        log "ERROR: $name: could not be turned off."
        failed=$((failed + 1))
    fi
}

disable_remote_management() {
    if ! pgrep -x ARDAgent >/dev/null 2>&1; then
        log "Remote Management: already off."
        return
    fi
    if [ ! -x "$ARD_KICKSTART" ]; then
        log "ERROR: Remote Management: kickstart not found."
        failed=$((failed + 1)); return
    fi
    "$ARD_KICKSTART" -deactivate -configure -access -off -stop >>"$LOG_FILE" 2>&1
    sleep 2
    if pgrep -x ARDAgent >/dev/null 2>&1; then
        log "ERROR: Remote Management: ARDAgent still running."
        failed=$((failed + 1))
    else
        log "Remote Management: turned off."
        changed=$((changed + 1))
    fi
}

disable_printer_sharing() {
    if ! cupsctl 2>/dev/null | grep -q '^_share_printers=1'; then
        log "Printer Sharing: already off."
        return
    fi
    if cupsctl --no-share-printers >>"$LOG_FILE" 2>&1 && ! cupsctl 2>/dev/null | grep -q '^_share_printers=1'; then
        log "Printer Sharing: turned off."
        changed=$((changed + 1))
    else
        log "ERROR: Printer Sharing: could not be turned off."
        failed=$((failed + 1))
    fi
}

disable_internet_sharing() {
    if ! defaults read "$NAT_PLIST" NAT 2>/dev/null | grep -q 'Enabled = 1'; then
        log "Internet Sharing: already off."
        return
    fi
    defaults write "$NAT_PLIST" NAT -dict-add Enabled -int 0 >>"$LOG_FILE" 2>&1
    if service_is_loaded "com.apple.InternetSharing"; then
        launchctl bootout system/com.apple.InternetSharing >>"$LOG_FILE" 2>&1
    fi
    if defaults read "$NAT_PLIST" NAT 2>/dev/null | grep -q 'Enabled = 1'; then
        log "ERROR: Internet Sharing: could not be turned off."
        failed=$((failed + 1))
    else
        log "Internet Sharing: turned off."
        changed=$((changed + 1))
    fi
}

disable_bluetooth_sharing() {
    local user uid current
    user=$(stat -f%Su /dev/console 2>/dev/null)
    if [ -z "$user" ] || [ "$user" = "root" ] || [ "$user" = "loginwindow" ]; then
        log "Bluetooth Sharing: no user signed in - checked again on the next run."
        return
    fi
    uid=$(id -u "$user" 2>/dev/null)
    current=$(launchctl asuser "$uid" sudo -u "$user" defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled 2>/dev/null)
    if [ "$current" = "0" ]; then
        log "Bluetooth Sharing: already off for the signed-in user."
        return
    fi
    launchctl asuser "$uid" sudo -u "$user" defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false >>"$LOG_FILE" 2>&1
    current=$(launchctl asuser "$uid" sudo -u "$user" defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled 2>/dev/null)
    if [ "$current" = "0" ]; then
        log "Bluetooth Sharing: turned off for the signed-in user."
        changed=$((changed + 1))
    else
        log "ERROR: Bluetooth Sharing: could not be turned off."
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

[ "$DISABLE_REMOTE_LOGIN" = true ]        && disable_service "com.openssh.sshd" "Remote Login (SSH)"
[ "$DISABLE_SCREEN_SHARING" = true ]      && disable_service "com.apple.screensharing" "Screen Sharing"
[ "$DISABLE_REMOTE_MANAGEMENT" = true ]   && disable_remote_management
[ "$DISABLE_FILE_SHARING" = true ]        && disable_service "com.apple.smbd" "File Sharing (SMB)"
[ "$DISABLE_REMOTE_APPLE_EVENTS" = true ] && disable_service "com.apple.AEServer" "Remote Apple Events"
[ "$DISABLE_PRINTER_SHARING" = true ]     && disable_printer_sharing
[ "$DISABLE_INTERNET_SHARING" = true ]    && disable_internet_sharing
[ "$DISABLE_BLUETOOTH_SHARING" = true ]   && disable_bluetooth_sharing

summary="Changed=$changed Failed=$failed"
[ "$failed" -gt 0 ] && finish 1 "FAILED: $summary"
finish 0 "OK: $summary"
