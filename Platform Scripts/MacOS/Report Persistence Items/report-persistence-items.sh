#!/bin/bash
###############################################################################
# report-persistence-items.sh   (Intune CUSTOM ATTRIBUTE for macOS)
#
# WHAT IT DOES
#   Inventories macOS persistence locations and reports items that are NOT on
#   your approved list:
#     - LaunchDaemons and LaunchAgents (system and per user)
#     - Activated system extensions (by Team ID)
#   Unsigned launchd programs are marked with '!'. Read-only: changes nothing.
#   Full details go to the log file; the attribute shows a short summary.
#
# OUTPUT (String, kept under 1,000 characters) - example
#   Unapproved=2; com.example.updater, !com.unknown.helper
#   Unapproved=0
#
# ACTIONS
#   1. Reads every *.plist in /Library/LaunchDaemons, /Library/LaunchAgents
#      and /Users/*/Library/LaunchAgents.
#   2. Label (file name) not starting with an APPROVED_LABEL_PREFIXES entry
#      -> unapproved. Program path checked with 'codesign -v'; unsigned -> '!'.
#   3. 'systemextensionsctl list': activated extensions whose Team ID isn't
#      in APPROVED_TEAM_IDS -> unapproved.
#   4. Echo the summary line (only output on stdout).
#
# INTUNE SETTINGS (Devices > By platform > macOS > Organize devices >
#   Custom attributes for macOS > Add)
#   Data type of attribute ... String
#   Runs every 8 hours as root.
#
# EXIT CODES
#   0 = report produced
#
# LOG
#   /Library/Logs/Microsoft/IntuneScripts/ReportPersistenceItems/ReportPersistenceItems.log
###############################################################################

set -u

# ----------------------------- SETTINGS --------------------------------------
# launchd label prefixes you approve. Add your organization's and vendors'.
APPROVED_LABEL_PREFIXES=("com.apple." "com.microsoft." "<your-org-prefix>.")
# Apple Developer Team IDs whose system extensions you approve.
# UBF8T346G9 = Microsoft Corporation (Defender for Endpoint, Intune).
APPROVED_TEAM_IDS=("UBF8T346G9")
# Maximum characters in the reported value.
MAX_RESULT_CHARS=1000
# ----------------------------------------------------------------------------

TASK_NAME="ReportPersistenceItems"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${TASK_NAME}"
LOG_FILE="${LOG_DIR}/${TASK_NAME}.log"
MAX_LOG_BYTES=1048576

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null; }

mkdir -p "$LOG_DIR" 2>/dev/null
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.1"
fi

unapproved=()

label_approved() {
    local label="$1" prefix
    for prefix in ${APPROVED_LABEL_PREFIXES[@]+"${APPROVED_LABEL_PREFIXES[@]}"}; do
        case "$label" in "$prefix"*) return 0 ;; esac
    done
    return 1
}

team_approved() {
    local team="$1" approved
    for approved in ${APPROVED_TEAM_IDS[@]+"${APPROVED_TEAM_IDS[@]}"}; do
        [ "$team" = "$approved" ] && return 0
    done
    return 1
}

# Prints the program path of launchd plist $1 (Program, else ProgramArguments[0]).
program_of() {
    plutil -extract Program raw -o - "$1" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$1" 2>/dev/null
}

check_plist() {
    local plist="$1" label program mark=""
    label=$(basename "$plist" .plist)
    program=$(program_of "$plist")
    if [ -n "$program" ] && [ -e "$program" ] && ! codesign -v "$program" >/dev/null 2>&1; then
        mark="!"
    fi
    if label_approved "$label"; then
        log "OK        $plist -> ${program:-?}"
    else
        log "UNAPPROVED${mark:+ (unsigned)} $plist -> ${program:-?}"
        unapproved+=("${mark}${label}")
    fi
}

log "===== Start ====="
for dir in /Library/LaunchDaemons /Library/LaunchAgents /Users/*/Library/LaunchAgents; do
    for plist in "$dir"/*.plist; do
        [ -f "$plist" ] && check_plist "$plist"
    done
done

# System extensions: lines look like
#   *  *  UBF8T346G9  com.microsoft.wdav.epsext (101.x/101.x)  Microsoft Defender ...  [activated enabled]
while IFS= read -r line; do
    case "$line" in *"[activated enabled]"*) ;; *) continue ;; esac
    team=$(echo "$line" | awk '{for (i=1;i<=NF;i++) if (length($i) == 10 && $i ~ /^[A-Z0-9]+$/) {print $i; exit}}')
    bundle=$(echo "$line" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+$/ && $i !~ /^[0-9.]+$/) {print $i; exit}}')
    if [ -n "$team" ] && team_approved "$team"; then
        log "OK        sysext $bundle ($team)"
    else
        log "UNAPPROVED sysext $bundle ($team)"
        unapproved+=("sysext:${bundle:-unknown}")
    fi
done < <(systemextensionsctl list 2>/dev/null)

count=${#unapproved[@]}
if [ "$count" -eq 0 ]; then
    result="Unapproved=0"
else
    list=$(printf '%s, ' "${unapproved[@]}")
    result="Unapproved=$count; ${list%, }"
fi
if [ "${#result}" -gt "$MAX_RESULT_CHARS" ]; then
    result="${result:0:$((MAX_RESULT_CHARS - 15))}... (see log)"
fi
log "$result"
echo "$result"
exit 0
