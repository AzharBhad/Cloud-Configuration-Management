# Harden Sudo (macOS)

Hardens **sudo** with a drop-in file in `/etc/sudoers.d` (**CIS macOS benchmark**). `timestamp_timeout=0` makes sudo ask for the password every time, so malware can't reuse a recent sudo session. `timestamp_type=tty` limits a ticket to the terminal that created it. `/etc/sudoers` itself is **never edited**, and every change is validated with `visudo` and rolled back if invalid.

**Why a script:** No configuration profile or declarative setting manages sudo.

## Files

| File | Purpose |
|---|---|
| `harden-sudo.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Baseline hardening | CIS control for admin and developer Macs. |
| Least-privilege programme | Pairs with [Remove Local Admin Rights](../Remove%20Local%20Admin%20Rights) for the remaining admins. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. | - |
| 2 | Include check | `/etc/sudoers` must include `/private/etc/sudoers.d` (macOS default). If not, fails **without editing sudoers**. | - |
| 3 | Already done? | Compares the drop-in with the wanted content. | Identical, so exits 0. |
| 4 | Validate | Writes a temp file and checks it with `visudo -cf`. | - |
| 5 | Install | Installs as `root:wheel 0440`, then checks everything with `visudo -c`. Rolls back if it fails. | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `TIMESTAMP_TIMEOUT` | `0` | Minutes a sudo ticket stays valid (0 = always ask) |
| `TIMESTAMP_TYPE` | `tty` | Ticket scope (`tty` = per terminal) |
| `DROPIN_FILE` | `/etc/sudoers.d/10_intune_sudo_hardening` | Drop-in path. The name must not contain `.`. |

```bash
TIMESTAMP_TIMEOUT=0
TIMESTAMP_TYPE="tty"
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 week**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/HardenSudo.lock`) stops two copies of this script running at once.
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
   - **Name**: `macOS - Harden Sudo`
   - **Description**: Requires the sudo password every time and limits sudo tickets to one terminal.
4. **Script settings**:
   - **Upload script**: `harden-sudo.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 week**. Re-applies if someone removes the file.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Harden Sudo > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/HardenSudo/HardenSudo.log"`. The last line is the summary.
4. Run `sudo cat /etc/sudoers.d/10_intune_sudo_hardening` and `sudo visudo -c` (all parsed OK). `sudo -k; sudo true; sudo true` asks for the password twice.

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Delete the drop-in: `sudo rm /etc/sudoers.d/10_intune_sudo_hardening`. Remove the assignment first, or the next weekly run puts it back.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/HardenSudo/HardenSudo.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./harden-sudo.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| Failed: *doesn't include /etc/sudoers.d* | `/etc/sudoers` was customised | Restore the macOS default sudoers, which includes the directory. |
| Failed: *didn't pass visudo* | Unsupported option on an old sudo | Check the log. macOS 12+ sudo supports both options. |
| Admins annoyed by frequent prompts | Expected with timeout 0 | Use a small timeout (for example `5`) if your security policy allows. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Hardening in place |
| 1 | Not root, include directory missing, or validation failed (nothing changed) |

