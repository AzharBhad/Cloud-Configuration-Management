# Harden Firewall and Time Sync (macOS)

Fills two gaps next to your firewall configuration profile. **Firewall**: turns on logging and stealth mode, and stops built-in or downloaded signed apps from being allowed through automatically. **Time**: turns on network time with your **corporate NTP server**. Accurate time is needed for Kerberos, certificates, Platform SSO and log correlation.

**Why a script:** On Macs **without** a firewall profile, these settings can only be set from the command line. Network time and the NTP server have no profile setting. When the firewall **is** managed by a profile, macOS blocks command-line changes; the script detects that and logs *managed by profile* instead of failing. Set `EnableLogging`, `EnableStealthMode`, `AllowSigned` and `AllowSignedApp` in that profile.

## Files

| File | Purpose |
|---|---|
| `harden-firewall-time-sync.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Firewall hardening (CIS 2.2.x / 3.x) | Logging and stealth mode on, no automatic exceptions. |
| Time-related sign-in failures | Kerberos and Platform SSO fail when clocks drift; this keeps time synced. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. | - |
| 2 | Firewall logging | `socketfilterfw --setloggingmode on` | Already on; managed by profile (logged); or setting false |
| 3 | Stealth mode | `--setstealthmode on` | Same |
| 4 | No auto-allow | `--setallowsigned off`, `--setallowsignedapp off` | Same |
| 5 | Network time | `systemsetup -setusingnetworktime on` and `-setnetworktimeserver <NTP_SERVER>` | Already set, or `CONFIGURE_TIME_SYNC=false` |
| 6 | Summary | Changed / ManagedByProfile / Failed | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `ENABLE_FIREWALL_LOGGING` | `true` | Firewall logging |
| `ENABLE_STEALTH_MODE` | `true` | Stealth mode |
| `BLOCK_AUTO_ALLOW_SIGNED` | `true` | Don't automatically allow signed apps |
| `CONFIGURE_TIME_SYNC` | `true` | Network time |
| `NTP_SERVER` | `time.apple.com` | NTP server. Use your internal NTP or domain controllers if you have them. |

```bash
NTP_SERVER="ntp.contoso.com"
BLOCK_AUTO_ALLOW_SIGNED=true
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/HardenFirewallTimeSync.lock`) stops two copies of this script running at once.
- The agent checks in every 8 hours. Users can trigger it with **Company Portal > the device > Check settings**.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |
| Full Disk Access (time settings) | Some `systemsetup` commands need Full Disk Access on recent macOS. If the time step fails, grant it to the Intune agent with a **PPPC** profile (`/new-configuration-policy`). |
| Firewall profile (optional) | If you use one, add `EnableLogging`, `EnableStealthMode`, `AllowSigned` and `AllowSignedApp` to it |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Manage devices > Scripts > Add**.
3. **Basics**:
   - **Name**: `macOS - Harden Firewall and Time Sync`
   - **Description**: Firewall logging, stealth mode, no auto-allow of signed apps; network time with the corporate NTP server.
4. **Script settings**:
   - **Upload script**: `harden-firewall-time-sync.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Re-applies the setting if it drifts.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Harden Firewall and Time Sync > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/HardenFirewallTimeSync/HardenFirewallTimeSync.log"`. The last line is the summary.
4. Run `/usr/libexec/ApplicationFirewall/socketfilterfw --getloggingmode --getstealthmode --getallowsigned` and `sudo systemsetup -getusingnetworktime -getnetworktimeserver`.

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Revert with `socketfilterfw --setloggingmode off`, `--setstealthmode off`, `--setallowsigned on`, `--setallowsignedapp on`, and `systemsetup -setnetworktimeserver time.apple.com`. Set the matching setting to `false` first.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/HardenFirewallTimeSync/HardenFirewallTimeSync.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./harden-firewall-time-sync.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| *ManagedByProfile* counts above 0 | The firewall profile manages these settings | Expected; set them in the profile. |
| Network time step fails | Missing Full Disk Access for the Intune agent | Deploy a PPPC profile granting it Full Disk Access. |
| An app stops receiving connections | Signed apps are no longer allowed automatically | Users or the profile must allow the app explicitly. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All settings applied, already set, or managed by a profile |
| 1 | Not root, or a setting couldn't be applied |

