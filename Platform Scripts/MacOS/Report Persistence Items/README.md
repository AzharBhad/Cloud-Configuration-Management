# Report Persistence Items (macOS custom attribute)

An Intune **custom attribute** that lists macOS **persistence items** that aren't on your approved list: LaunchDaemons and LaunchAgents (system and per user), and activated **system extensions** (by Team ID). Unsigned launchd programs are marked with `!`. Read-only. Full details are in the log.

**Why a script:** Persistence is how macOS malware and grey-area tools survive a restart. Defender detects known threats, but an inventory against an allow list shows policy drift and unknown tools. A custom attribute shows the count per Mac every 8 hours.

## Files

| File | Purpose |
|---|---|
| `report-persistence-items.sh` | The script you upload to Intune as a **custom attribute**. |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Threat hunting | Find Macs with unknown launch jobs or unsigned helpers. |
| Software governance | Find tools that install background services without approval. |
| Before enforcing Remove Prohibited Apps | See what's out there first. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | launchd | Reads every plist in `/Library/LaunchDaemons`, `/Library/LaunchAgents` and `/Users/*/Library/LaunchAgents`. | - |
| 2 | Approve or flag | Labels not starting with an `APPROVED_LABEL_PREFIXES` entry are unapproved. The program is checked with `codesign -v` (unsigned = `!`). | - |
| 3 | System extensions | `systemextensionsctl list`: activated extensions whose Team ID isn't in `APPROVED_TEAM_IDS` are unapproved. | - |
| 4 | Report | `Unapproved=N; item, item…` (under 1,000 characters). Full list in the log. | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `APPROVED_LABEL_PREFIXES` | `com.apple.` `com.microsoft.` `<your-org-prefix>.` | launchd label prefixes you approve. **Replace the placeholder** and add your vendors. |
| `APPROVED_TEAM_IDS` | `UBF8T346G9` (Microsoft) | Apple Developer Team IDs whose system extensions you approve |
| `MAX_RESULT_CHARS` | `1000` | Maximum length of the reported value |

```bash
APPROVED_LABEL_PREFIXES=("com.apple." "com.microsoft." "com.contoso." "com.zoom.")
APPROVED_TEAM_IDS=("UBF8T346G9" "BJ4HAAB9B3")   # Microsoft, Zoom
```

## How Intune runs it

- Custom attribute scripts run **as root every 8 hours** on each Mac through the Intune management agent, and report the echoed value.
- Result: **Success** (exit 0) shows the value in the **Result** column. **Failed** (non-zero exit or malformed script) shows the error.
- The value must be **20 KB or less**; this script keeps it short. Full details are in the log file.
- Read-only. A Mac with many approved items still reports `Unapproved=0`.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Organize devices > Custom attributes for macOS > Add**.
3. **Basics**:
   - **Name**: `macOS - Unapproved Persistence Items`
   - **Description**: Reports LaunchDaemons, LaunchAgents and system extensions not on the approved list.
4. **Attribute settings**:
   - **Data type of attribute**: **String**. The script echoes one text line.
   - **Script**: upload `report-persistence-items.sh`.
5. **Assignments**: start with a **pilot device group**, then all corporate Macs. Device groups are recommended; with user groups the attribute runs on any Mac the user signs in to.
6. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Organize devices > Custom attributes for macOS > macOS - Unapproved Persistence Items > Device status**.
2. The **Result** column shows the value per Mac, for example `Unapproved=2; com.example.updater, !com.unknown.helper`.
3. Export the list (CSV) and filter for the values that need action (see "Typical actions").
4. On a Mac, check the details with `sudo cat "/Library/Logs/Microsoft/IntuneScripts/ReportPersistenceItems/ReportPersistenceItems.log"`.

## Running it again

Custom attributes re-run automatically every 8 hours. Upload a changed script to change what is reported.

## Undo

Nothing to undo (read-only). Delete the custom attribute to stop reporting.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/ReportPersistenceItems/ReportPersistenceItems.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./report-persistence-items.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| Too many unapproved items | Allow list too short | Add trusted vendor prefixes and Team IDs (find them with `codesign -dv --verbose=2 <app>`). |
| Value ends with *(see log)* | Result longer than `MAX_RESULT_CHARS` | Read the full list in the log on the Mac. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Report produced |

