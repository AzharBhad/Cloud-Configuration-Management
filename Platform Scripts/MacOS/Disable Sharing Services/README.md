# Disable Sharing Services (macOS)

Turns off macOS **sharing and remote-access services** that expose the Mac to the network: Remote Login (SSH), Screen Sharing, Remote Management (ARD), File Sharing (SMB), Remote Apple Events, Printer Sharing, Internet Sharing and Bluetooth Sharing. These are **CIS macOS benchmark** controls that close lateral-movement and data-exfiltration paths. Each service can be kept on through a setting.

**Why a script:** Restrictions profiles cover only part of this (for example AirDrop and content caching). Most sharing services have no complete profile or declarative setting. The script uses `launchctl`, which doesn't need Full Disk Access.

## Files

| File | Purpose |
|---|---|
| `disable-sharing-services.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Baseline hardening | One control for all sharing services on every corporate Mac. |
| Drift | A user or technician turned on Screen Sharing or SSH; the daily run turns it off again. |
| Audit (CIS 2.3.x) | The log shows each service's state and change. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. | - |
| 2 | Remote Login (SSH) | `launchctl disable` + `bootout system/com.openssh.sshd` | Already disabled and not loaded, or `DISABLE_REMOTE_LOGIN=false` |
| 3 | Screen Sharing | Same for `com.apple.screensharing` | Already off, or setting false |
| 4 | Remote Management | ARD `kickstart -deactivate -configure -access -off -stop` | ARDAgent not running, or setting false |
| 5 | File Sharing (SMB) | Same for `com.apple.smbd` | Already off, or setting false |
| 6 | Remote Apple Events | Same for `com.apple.AEServer` | Already off, or setting false |
| 7 | Printer Sharing | `cupsctl --no-share-printers` | Not shared, or setting false |
| 8 | Internet Sharing | `com.apple.nat` NAT Enabled = 0, and stops `com.apple.InternetSharing` | Already off, or setting false |
| 9 | Bluetooth Sharing | For the **signed-in user**: `PrefKeyServicesEnabled = false` (run as that user) | No user signed in (checked on the next run), already off, or setting false |
| 10 | Summary | Changed / Failed counts | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `DISABLE_REMOTE_LOGIN` | `true` | SSH |
| `DISABLE_SCREEN_SHARING` | `true` | Screen Sharing |
| `DISABLE_REMOTE_MANAGEMENT` | `true` | Apple Remote Desktop agent. Set to `false` if you support Macs with ARD. |
| `DISABLE_FILE_SHARING` | `true` | SMB file sharing |
| `DISABLE_REMOTE_APPLE_EVENTS` | `true` | Remote Apple Events |
| `DISABLE_PRINTER_SHARING` | `true` | Printer sharing (CUPS) |
| `DISABLE_INTERNET_SHARING` | `true` | Internet Sharing (NAT) |
| `DISABLE_BLUETOOTH_SHARING` | `true` | Bluetooth file sharing, per user |

```bash
DISABLE_REMOTE_LOGIN=false       # developers need SSH (use a separate device group)
DISABLE_REMOTE_MANAGEMENT=true
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/DisableSharingServices.lock`) stops two copies of this script running at once.
- The agent checks in every 8 hours. Users can trigger it with **Company Portal > the device > Check settings**.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Manage devices > Scripts > Add**.
3. **Basics**:
   - **Name**: `macOS - Disable Sharing Services`
   - **Description**: Turns off SSH, Screen Sharing, Remote Management, SMB, Remote Apple Events, Printer, Internet and Bluetooth sharing.
4. **Script settings**:
   - **Upload script**: `disable-sharing-services.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Re-applies the setting if it drifts.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in. Put Macs that legitimately need a service (for example developer Macs with SSH) in an **exclusion group**, or give them a copy of the script with that setting `false`.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Disable Sharing Services > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/DisableSharingServices/DisableSharingServices.log"`. The last line is the summary.
4. Check `sudo launchctl print-disabled system | grep -E 'sshd|screensharing|smbd|AEServer'` (all `disabled`), `cupsctl | grep _share_printers` (`=0`), and **System Settings > General > Sharing** (all off).

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Turn a service back on in **System Settings > General > Sharing**, or with `sudo launchctl enable system/<label>` and `sudo launchctl bootstrap`. Set its setting to `false` first, or the next run turns it off again.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/DisableSharingServices/DisableSharingServices.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./disable-sharing-services.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| SSH or Screen Sharing comes back on | The user turns it on again in Sharing | Expected: the next daily run turns it off. Consider blocking with a restrictions profile where available. |
| Bluetooth Sharing not changed | No user signed in during the run | It's handled on the next run while a user is signed in. |
| Remote Management still on | ARD managed by another MDM payload or tool | Remove the other management, or set `DISABLE_REMOTE_MANAGEMENT=false`. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Every selected service is off |
| 1 | Not root, or a service couldn't be turned off |

