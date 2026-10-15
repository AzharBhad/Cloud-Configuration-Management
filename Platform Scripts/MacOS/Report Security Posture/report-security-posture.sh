#!/bin/bash
###############################################################################
# report-security-posture.sh   (Intune CUSTOM ATTRIBUTE for macOS)
#
# WHAT IT DOES
#   Reports the Mac's core security controls in one line so you can find
#   Macs where System Integrity Protection (SIP) or Gatekeeper was turned off,
#   the firewall is off, FileVault is off, XProtect is outdated, or Activation
#   Lock is on (a corporate Mac locked to a personal Apple Account).
#   Read-only: changes nothing. A script can't turn SIP back on (that needs
#   Recovery), so this report is how you find those Macs.
#
# OUTPUT (String) - example
#   OS=15.1(24B83); Arch=arm64; SIP=enabled; Gatekeeper=enabled; Firewall=enabled; FileVault=On; XProtect=5300; ActivationLock=Disabled
#
# ACTIONS
#   1. sw_vers / uname -m ............... OS version, build, architecture
#   2. csrutil status .................. SIP enabled / disabled / custom
#   3. spctl --status .................. Gatekeeper enabled / disabled
#   4. socketfilterfw --getglobalstate . Firewall enabled / disabled / blockall
#   5. fdesetup status ................. FileVault On / Off
#   6. XProtect.bundle Info.plist ...... XProtect version
#   7. system_profiler SPHardwareDataType Activation Lock status
#   8. Echo the single result line (only output on stdout).
#
# INTUNE SETTINGS (Devices > By platform > macOS > Organize devices >
#   Custom attributes for macOS > Add)
#   Data type of attribute ... String
#   Runs every 8 hours as root.
#
# EXIT CODES
#   0 = value reported (individual checks show "unknown" if they fail)
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/ReportSecurityPosture/ReportSecurityPosture.log
###############################################################################

set -u

TASK_NAME="ReportSecurityPosture"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
MAX_LOG_BYTES=1048576
FIREWALL_CLI="/usr/libexec/ApplicationFirewall/socketfilterfw"
XPROTECT_PLIST="/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null; }

mkdir -p "$LOG_DIR" 2>/dev/null
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.1"
fi

parse_sip() {
    case "$1" in
        *"Custom Configuration"*|*"unknown"*) echo "custom" ;;
        *"status: enabled"*) echo "enabled" ;;
        *"status: disabled"*) echo "disabled" ;;
        *) echo "unknown" ;;
    esac
}

parse_gatekeeper() {
    case "$1" in
        *"assessments enabled"*) echo "enabled" ;;
        *"assessments disabled"*) echo "disabled" ;;
        *) echo "unknown" ;;
    esac
}

parse_firewall() {
    case "$1" in
        *"State = 2"*|*"blocking all"*) echo "blockall" ;;
        *"State = 1"*|*"is enabled"*) echo "enabled" ;;
        *"State = 0"*|*"is disabled"*) echo "disabled" ;;
        *) echo "unknown" ;;
    esac
}

parse_filevault() {
    case "$1" in
        *"FileVault is On"*) echo "On" ;;
        *"in progress"*) echo "InProgress" ;;
        *"FileVault is Off"*) echo "Off" ;;
        *) echo "unknown" ;;
    esac
}

os="$(sw_vers -productVersion 2>/dev/null)($(sw_vers -buildVersion 2>/dev/null))"
arch=$(uname -m 2>/dev/null)
sip=$(parse_sip "$(csrutil status 2>&1)")
gatekeeper=$(parse_gatekeeper "$(spctl --status 2>&1)")
firewall=$(parse_firewall "$("$FIREWALL_CLI" --getglobalstate 2>&1)")
filevault=$(parse_filevault "$(fdesetup status 2>&1)")
xprotect=$(defaults read "$XPROTECT_PLIST" CFBundleShortVersionString 2>/dev/null)
[ -n "$xprotect" ] || xprotect="unknown"
activation_lock=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Activation Lock Status/ {print $2; exit}')
[ -n "$activation_lock" ] || activation_lock="unknown"

result="OS=$os; Arch=$arch; SIP=$sip; Gatekeeper=$gatekeeper; Firewall=$firewall; FileVault=$filevault; XProtect=$xprotect; ActivationLock=$activation_lock"
log "$result"
echo "$result"
exit 0
