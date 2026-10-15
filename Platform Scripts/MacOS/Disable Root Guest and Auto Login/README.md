# Disable Root, Guest and Auto Login (macOS)

Closes **local-access gaps** that come back after migrations, manual support or old images. It disables the **root user**, turns off the **Guest** account and guest access to shared folders, removes a leftover Guest home folder, and removes **automatic login** and its saved password (`/etc/kcpassword`).

**Why a script:** Login window profiles can hide or block Guest at sign-in, but nothing disables an already-enabled root user or removes a saved auto-login password. A daily script also undoes local changes.

## Files

| File | Purpose |
|---|---|
| `disable-root-guest-autologin.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Baseline hardening | CIS controls 5.x (root disabled, Guest off, no automatic login). |
| After support or migration | A technician enabled root or auto login and forgot to turn it off. |
| Shared and kiosk-like Macs | Makes sure no account signs in without credentials. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. | - |
| 2 | Root user | If `/Users/root` has an `AuthenticationAuthority` (a password is set), deletes it and sets the password to `*` (disabled). | Already disabled, or `DISABLE_ROOT=false` |
| 3 | Guest | `sysadminctl -guestAccount off`, `GuestEnabled=false`, `sysadminctl -smbGuestAccess off`. Removes a leftover `/Users/Guest` only when no Guest user exists. | Already off, or `DISABLE_GUEST=false` |
| 4 | Automatic login | Deletes `autoLoginUser` and `/etc/kcpassword`. | Not configured, or `DISABLE_AUTO_LOGIN=false` |
| 5 | Summary | Changed / Failed | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `DISABLE_ROOT` | `true` | Disable the root user |
| `DISABLE_GUEST` | `true` | Turn off Guest and guest share access |
| `DISABLE_AUTO_LOGIN` | `true` | Remove automatic login |

```bash
DISABLE_ROOT=true
DISABLE_GUEST=true
DISABLE_AUTO_LOGIN=true
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/DisableRootGuestAutoLogin.lock`) stops two copies of this script running at once.
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
   - **Name**: `macOS - Disable Root, Guest and Auto Login`
   - **Description**: Disables the root user, the Guest account and guest share access, and removes automatic login.
4. **Script settings**:
   - **Upload script**: `disable-root-guest-autologin.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Re-applies the setting if it drifts.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Disable Root, Guest and Auto Login > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/DisableRootGuestAutoLogin/DisableRootGuestAutoLogin.log"`. The last line is the summary.
4. Run `dscl . -read /Users/root AuthenticationAuthority` (should say *No such key*), `defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled` (0) and `ls /etc/kcpassword` (not found).

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Root: `sudo dsenableroot` (not recommended). Guest: **System Settings > Users & Groups > Guest User**. Auto login: **Users & Groups > Automatically log in as**. Set the matching setting to `false` first.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/DisableRootGuestAutoLogin/DisableRootGuestAutoLogin.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./disable-root-guest-autologin.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| Guest still listed at the login window | Login window cache | Restart, or deploy a login window profile that hides Guest. |
| Auto login comes back | The user turns it on again | The next run removes it. FileVault also blocks auto login. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All items in the wanted state |
| 1 | Not root, or an item couldn't be fixed |

