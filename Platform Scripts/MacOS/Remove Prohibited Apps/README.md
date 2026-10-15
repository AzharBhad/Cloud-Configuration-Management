# Remove Prohibited Apps (macOS)

Finds and removes **apps your organization prohibits**, for example unsanctioned remote-access tools, P2P/torrent clients and crypto miners, that users installed themselves. It stops their processes, unloads and deletes their **launchd jobs**, and deletes the **app bundles**. It starts in **DRY RUN** (report only).

**Why a script:** Intune can only uninstall apps it deployed. Shadow-IT remote-access tools are a common attacker foothold, and there's no profile that removes them.

## Files

| File | Purpose |
|---|---|
| `remove-prohibited-apps.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Shadow IT clean-up | Remove tools that bypass your approved remote-support solution. |
| Incident response | Remove a tool flagged by Defender or the SOC from all Macs quickly. |
| Licence and compliance | Remove software your organization doesn't licence. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. | - |
| 2 | launchd jobs | Plists in `/Library/LaunchDaemons`, `/Library/LaunchAgents` and `~/Library/LaunchAgents` matching `LAUNCHD_PREFIXES`: bootout, then delete. | No match, or `DRY_RUN=true` (logged only) |
| 3 | Processes | `pkill -x` for each `PROCESS_NAMES` entry | Not running, or dry run |
| 4 | App bundles | Deletes each `APP_NAMES` entry in `/Applications`, `/Applications/Utilities` and `~/Applications` (real folders only, never symlinks) | Not found, or dry run |
| 5 | Summary | Found / Removed / Failed | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `APP_NAMES` | Example list | App bundle names to delete. **Replace the examples with your list.** |
| `PROCESS_NAMES` | Example list | Process names to stop |
| `LAUNCHD_PREFIXES` | Example list | Start of the launchd plist file names to remove |
| `DRY_RUN` | `true` | Report only. Set to `false` after reviewing the pilot log. |

```bash
APP_NAMES=("AnyDesk.app" "uTorrent Web.app")
PROCESS_NAMES=("AnyDesk" "uTorrent Web")
LAUNCHD_PREFIXES=("com.philandro.anydesk")
DRY_RUN=false
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/RemoveProhibitedApps.lock`) stops two copies of this script running at once.
- The agent checks in every 8 hours. Users can trigger it with **Company Portal > the device > Check settings**.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |
| Approved list | A documented prohibited-software list, signed off by security |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Manage devices > Scripts > Add**.
3. **Basics**:
   - **Name**: `macOS - Remove Prohibited Apps`
   - **Description**: Removes unapproved apps (remote-access tools, P2P clients, miners): processes, launchd jobs and app bundles.
4. **Script settings**:
   - **Upload script**: `remove-prohibited-apps.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Removes the apps again if users reinstall them.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in. **Remove from the lists any tool your organization approves**; the examples include products some organizations sanction.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Remove Prohibited Apps > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/RemoveProhibitedApps/RemoveProhibitedApps.log"`. The last line is the summary.
4. Check the log for *Deleted* and *Removed launchd job* lines, and `ls /Applications`.

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Reinstall the app (deleted apps can't be restored by the script). Remove its entries from the lists, or exclude the Mac, first.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/RemoveProhibitedApps/RemoveProhibitedApps.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./remove-prohibited-apps.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| App comes back | The user reinstalls it | The next run removes it again. Consider blocking with Defender indicators or an app control solution. |
| App not found | Installed somewhere else, or a different bundle name | Check the path with `mdfind 'kMDItemCFBundleIdentifier == "<id>"'` and adjust `APP_NAMES`. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Nothing found, all removed, or dry run |
| 1 | Not root, or something couldn't be removed |

