#!/bin/bash
###############################################################################
# report-filevault-status.sh   (Intune CUSTOM ATTRIBUTE for macOS)
#
# WHAT IT DOES
#   Reports the FileVault state of the Mac as one line, so you can find Macs
#   where encryption is off, still in progress, deferred until next sign-in,
#   or has no personal recovery key (PRK) to escrow to Intune.
#   Read-only: changes nothing.
#
# OUTPUT (String) - example
#   Status=On; PRK=true; Deferred=false
#   Status values: On | Off | Encrypting | Decrypting | Deferred | Unknown
#
# ACTIONS
#   1. fdesetup status ................ On / Off / in progress / deferred
#   2. fdesetup haspersonalrecoverykey  true / false
#   3. fdesetup showdeferralinfo ...... deferral pending for a user?
#   4. Echo the single result line (only output on stdout).
#
# INTUNE SETTINGS (Devices > By platform > macOS > Organize devices >
#   Custom attributes for macOS > Add)
#   Data type of attribute ... String
#   Runs every 8 hours as root; result in the Device status "Result" column.
#
# EXIT CODES
#   0 = value reported
#   1 = fdesetup not available (result shows "Unknown")
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/ReportFileVaultStatus/ReportFileVaultStatus.log
###############################################################################

set -u

TASK_NAME="ReportFileVaultStatus"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
MAX_LOG_BYTES=1048576

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null; }

mkdir -p "$LOG_DIR" 2>/dev/null
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.1"
fi

# Maps the text of 'fdesetup status' to a short status word.
parse_status() {
    case "$1" in
        *"will be enabled after the next restart"*|*"Deferred enablement"*) echo "Deferred" ;;
        *"Encryption in progress"*) echo "Encrypting" ;;
        *"Decryption in progress"*) echo "Decrypting" ;;
        *"FileVault is On"*) echo "On" ;;
        *"FileVault is Off"*) echo "Off" ;;
        *) echo "Unknown" ;;
    esac
}

if ! command -v fdesetup >/dev/null 2>&1; then
    log "fdesetup not found."
    echo "Status=Unknown; PRK=unknown; Deferred=unknown"
    exit 1
fi

raw_status=$(fdesetup status 2>&1)
status=$(parse_status "$raw_status")

prk=$(fdesetup haspersonalrecoverykey 2>/dev/null)
case "$prk" in true|false) ;; *) prk="unknown" ;; esac

deferral=$(fdesetup showdeferralinfo 2>&1)
case "$deferral" in
    *"Not found"*|"") deferred=false ;;
    *) deferred=true ;;
esac
[ "$status" = "Deferred" ] && deferred=true

log "fdesetup status: $(echo "$raw_status" | tr '\n' ' ')"
log "PRK=$prk Deferred=$deferred"

echo "Status=$status; PRK=$prk; Deferred=$deferred"
exit 0
