# Remove Local Admin Rights (macOS)

Removes **local administrator rights** from every user on a Mac except the approved admin accounts, typically the local admin account created during Automated Device Enrollment and managed by Intune (LAPS). Users become **standard users**. Their data, passwords and FileVault access (Secure Token) aren't changed.

**Why a script:** No macOS configuration profile or declarative setting removes existing users from the admin group. Account creation settings only affect new accounts during setup. A daily script also catches admins added later.

## Files

| File | Purpose |
|---|---|
| `remove-local-admin-rights.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Least-privilege rollout | Removes admin rights from existing Macs in one step. |
| Macs enrolled before ADE standard-user setup | Converts users created as admins during setup. |
| Drift | Someone added a user to admin for troubleshooting; the next daily run removes it. |
| Audit evidence | The log shows who was demoted and when. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Must run as root; lock against parallel runs. | - |
| 2 | Safety check | Confirms at least one **approved** admin exists, is enabled and is in the admin group. Otherwise it **stops with no changes**, so the Mac is never left without an admin. | - |
| 3 | Read admins | Reads the members of the local `admin` group. | - |
| 4 | Demote | Removes each unapproved user with `dseditgroup -o edit -d <user> -t user admin`, then confirms with `dsmemberutil`. | root, approved accounts, `_` system accounts, UID below 501, names with no local user record (for example directory groups) |
| 5 | Summary | One line: Removed / Failed / Skipped. | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `APPROVED_ADMINS` | `("<managed-admin-account>")` | Account names that keep admin rights. **Replace the placeholder** with your ADE/LAPS admin account name, plus any other approved accounts. |
| `DRY_RUN` | `false` | `true` = only log who would be removed. Use this for the pilot. |
| `MIN_USER_UID` | `501` | Accounts below this UID are system accounts and are skipped. |

```bash
APPROVED_ADMINS=("macadmin" "helpdesk-breakglass")
DRY_RUN=true          # pilot first, then false
MIN_USER_UID=501
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs a few seconds.
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/RemoveLocalAdminRights.lock`) stops two copies of this script running at once.
- The agent checks in every 8 hours. Users can trigger it with **Company Portal > the device > Check settings**.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |
| Managed admin | An approved local admin account exists on every Mac (ADE local admin account with Intune LAPS recommended). **Without it the script deliberately fails.** |
| Elevation process | A way for users to get temporary admin rights when justified (for example a privilege-management tool) |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Manage devices > Scripts > Add**.
3. **Basics**:
   - **Name**: `macOS - Remove Local Admin Rights`
   - **Description**: Removes local admin rights from all users except the approved managed admin account.
4. **Script settings**:
   - **Upload script**: `remove-local-admin-rights.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Removes admin rights that are granted again later.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Remove Local Admin Rights > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/RemoveLocalAdminRights/RemoveLocalAdminRights.log"`. The last line is the summary.
4. Run `dscl . -read /Groups/admin GroupMembership`. Only root and the approved accounts should remain.

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Add a user back as admin with `sudo dseditgroup -o edit -a <user> -t user admin`. Exclude that Mac from the assignment, or add the user to `APPROVED_ADMINS`, or the next run removes them again.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/RemoveLocalAdminRights/RemoveLocalAdminRights.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./remove-local-admin-rights.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| Failed: *no approved admin account found* | `APPROVED_ADMINS` still has the placeholder, or the account is missing or disabled | Set the correct account name. Make sure the ADE admin account exists. |
| User still admin | Admin rights come through a nested group or directory group | Remove the nested group, or manage it at the directory. |
| User loses rights mid-session | Expected | Already-open admin sessions (for example a running installer) finish; new prompts need an admin. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success: nothing to do, unapproved admins removed, or dry run |
| 1 | Not root, safety check failed, or a removal failed |

