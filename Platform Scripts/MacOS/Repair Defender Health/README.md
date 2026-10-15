# Repair Defender Health (macOS)

Checks **Microsoft Defender for Endpoint** on the Mac with `mdatp health`. It fixes what a script can (updates security intelligence, turns real-time protection back on when policy doesn't manage it) and reports what it can't (not onboarded, no Full Disk Access, system extension not approved) as **Failed** in Intune. A Mac that looks protected but isn't creates false confidence, and breaks the Defender risk score your compliance policies rely on.

**Why a script:** Configuration profiles deploy Defender's settings and permissions, but nothing checks the running agent's health and fixes it. Defender has no Intune health-repair feature on macOS.

## Files

| File | Purpose |
|---|---|
| `repair-defender-health.sh` | The script you upload to Intune (**Platform scripts** for macOS). |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Daily health check | Finds Macs where Defender is unhealthy, with the reason, in Device status. |
| After macOS upgrades | Extensions or permissions can reset; this shows which Macs need attention. |
| Stale intelligence | Forces a security intelligence update. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Checks | Root + lock. Stops (Failed) if `mdatp` isn't installed. | - |
| 2 | Read health | `healthy`, `health_issues`, `licensed`, `org_id`, `real_time_protection_enabled/available`, `full_disk_access_enabled`, `tamper_protection` | - |
| 3 | Update intelligence | `mdatp definitions update`, with a timeout (`DEFINITIONS_TIMEOUT`) | - |
| 4 | Real-time protection | `mdatp config real-time-protection --value enabled` | Already on, or `REPAIR_REAL_TIME_PROTECTION=false`. Fails harmlessly when policy or tamper protection manages it. |
| 5 | Re-check | Reads health again. Any remaining problem = Failed, with the reasons. | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| `MDATP` | `/usr/local/bin/mdatp` | Path to the Defender CLI |
| `DEFINITIONS_TIMEOUT` | `600` | Seconds to wait for the intelligence update |
| `REPAIR_REAL_TIME_PROTECTION` | `true` | Try to turn real-time protection on |
| `REQUIRE_EDR_ONBOARDING` | `true` | Report Macs without an `org_id` (not onboarded) as failed |

```bash
DEFINITIONS_TIMEOUT=900
REQUIRE_EDR_ONBOARDING=true
```

## How Intune runs it

- Runs **as root** through the Intune management agent **every 1 day**, and also after each restart. The script is idempotent, so repeated runs change nothing once the Mac is compliant.
- **Status** is reported when it changes (Success / Failed), and the timestamp refreshes every 7 days. Not every run is reported.
- **Retries**: up to 3 on failure (exit 1).
- **Timeout**: stopped and marked failed after 60 minutes. This script needs up to about 10 minutes (intelligence update).
- **Parallel runs**: Intune runs macOS scripts in parallel. A lock folder (`/tmp/RepairDefenderHealth.lock`) stops two copies of this script running at once.
- The agent checks in every 8 hours. Users can trigger it with **Company Portal > the device > Check settings**.

## Prerequisites

| Requirement | Details |
|---|---|
| macOS | macOS 12.0 or later (Apple silicon and Intel) |
| Management | Intune-enrolled Mac. The **Microsoft Intune management agent** is installed automatically when a script or custom attribute is assigned. |
| Network | Direct internet connection. Intune shell scripts **don't support proxies**. |
| Role | Intune role with **Device configurations** permissions |
| Defender for Endpoint | Installed and onboarded with the Intune Defender for Endpoint profiles: onboarding, system extensions, Full Disk Access (PPPC), network filter, notifications |
| License | Microsoft Defender for Endpoint P1/P2, or Microsoft 365 E5 / E5 Security |

## Step-by-step: add the script in Intune

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > By platform > macOS > Manage devices > Scripts > Add**.
3. **Basics**:
   - **Name**: `macOS - Repair Defender for Endpoint Health`
   - **Description**: Checks Microsoft Defender for Endpoint health, updates intelligence, re-enables real-time protection, and reports what can't be fixed.
4. **Script settings**:
   - **Upload script**: `repair-defender-health.sh`
   - **Run script as signed-in user**: **No**, so it runs as root. The changes are system-wide and need root.
   - **Hide script notifications on devices**: **Yes**. It's a silent background control.
   - **Script frequency**: **Every 1 day**. Re-applies the setting if it drifts.
   - **Max number of times to retry if script fails**: **3**.
5. **Scope tags**: add your macOS admin scope tag (for example **Mac Admin**) if you use one.
6. **Assignments**: add a **pilot device group** first, then all corporate Macs. Use device groups, so the script runs whether or not a user is signed in.
7. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Manage devices > Scripts > macOS - Repair Defender for Endpoint Health > Device status**.
2. **Success** = exit 0. **Failed** = exit 1. The reason is in the script log on the Mac.
3. On a Mac, read the log: `sudo tail -50 "/Library/Logs/Microsoft/IntuneScripts/RepairDefenderHealth/RepairDefenderHealth.log"`. The last line is the summary.
4. Run `mdatp health`. `healthy : true`, `real_time_protection_enabled : true`, `licensed : true`, and an `org_id` should be shown.

## Running it again

The script already re-runs on its frequency and after each restart. To force a new run sooner, upload a changed script (it's treated as a new script), or ask the user to select **Check settings** in Company Portal.

## Undo

Nothing to undo. The script only updates intelligence and turns protection back on. Remove the assignment to stop it.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/RepairDefenderHealth/RepairDefenderHealth.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./repair-defender-health.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| Failed: *no Full Disk Access* | PPPC profile missing or not approved | Deploy the Defender Full Disk Access (PPPC) profile. |
| Failed: *RTP unavailable* | System extension not approved | Deploy the Defender system extensions profile; check `systemextensionsctl list`. |
| Failed: *EDR not onboarded* | Onboarding profile missing | Deploy the Defender for Endpoint onboarding profile. |
| Can't turn on real-time protection | Managed by policy or tamper protection | Fix the Defender preferences policy in Intune. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Defender healthy (after repair if needed) |
| 1 | Not root, Defender missing, or still unhealthy |

