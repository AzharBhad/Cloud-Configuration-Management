# Report Security Posture (macOS custom attribute)

An Intune **custom attribute** that reports the Mac's core security controls in one line: macOS version, architecture, **System Integrity Protection (SIP)**, **Gatekeeper**, **firewall**, **FileVault**, **XProtect** version and **Activation Lock**. Read-only.

**Why a script:** A script **can't** turn SIP back on (it needs Recovery), and some of these values aren't in Intune's hardware inventory. A custom attribute finds tampered or misconfigured Macs every 8 hours, so you can remediate them or block them with Conditional Access through compliance.

## Files

| File | Purpose |
|---|---|
| `report-security-posture.sh` | The script you upload to Intune as a **custom attribute**. |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Tamper detection | `SIP=disabled` or `Gatekeeper=disabled` means a user or attacker weakened the Mac. |
| Corporate asset protection | `ActivationLock=Enabled` on a corporate Mac (personal Apple Account) blocks wipe and reuse. Clear it with the MDM bypass code. |
| Patch and XProtect hygiene | Find Macs on old macOS or XProtect versions. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | OS | `sw_vers` version and build; `uname -m` architecture | - |
| 2 | SIP | `csrutil status`: enabled / disabled / custom | - |
| 3 | Gatekeeper | `spctl --status` | - |
| 4 | Firewall | `socketfilterfw --getglobalstate`: enabled / disabled / blockall | - |
| 5 | FileVault | `fdesetup status` | - |
| 6 | XProtect | Version from `XProtect.bundle` | - |
| 7 | Activation Lock | `system_profiler SPHardwareDataType` | - |
| 8 | Report | Echoes one line. Each failed check shows `unknown`. | - |

## Settings in the script

Edit the **SETTINGS** block at the top of the script before uploading it.

| Variable | Default | Meaning |
|---|---|---|
| (none) | - | The script has no settings. |

```bash
# No settings - upload as-is.
```

## How Intune runs it

- Custom attribute scripts run **as root every 8 hours** on each Mac through the Intune management agent, and report the echoed value.
- Result: **Success** (exit 0) shows the value in the **Result** column. **Failed** (non-zero exit or malformed script) shows the error.
- The value must be **20 KB or less**; this script keeps it short. Full details are in the log file.
- The script is read-only, so running it often has no side effects.

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
   - **Name**: `macOS - Security Posture`
   - **Description**: Reports OS, SIP, Gatekeeper, firewall, FileVault, XProtect version and Activation Lock.
4. **Attribute settings**:
   - **Data type of attribute**: **String**. The script echoes one text line.
   - **Script**: upload `report-security-posture.sh`.
5. **Assignments**: start with a **pilot device group**, then all corporate Macs. Device groups are recommended; with user groups the attribute runs on any Mac the user signs in to.
6. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Organize devices > Custom attributes for macOS > macOS - Security Posture > Device status**.
2. The **Result** column shows the value per Mac, for example `OS=15.1(24B83); Arch=arm64; SIP=enabled; Gatekeeper=enabled; Firewall=enabled; FileVault=On; XProtect=5300; ActivationLock=Disabled`.
3. Export the list (CSV) and filter for the values that need action (see "Typical actions").
4. On a Mac, check the details with `sudo cat "/Library/Logs/Microsoft/IntuneScripts/ReportSecurityPosture/ReportSecurityPosture.log"`.

## Running it again

Custom attributes re-run automatically every 8 hours. Upload a changed script to change what is reported.

## Undo

Nothing to undo (read-only). Delete the custom attribute to stop reporting.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/ReportSecurityPosture/ReportSecurityPosture.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./report-security-posture.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| `SIP=disabled` | Disabled in Recovery (`csrutil disable`) | Re-enable from Recovery (`csrutil enable`), or wipe and re-provision. Treat it as a security incident if unexplained. |
| `ActivationLock=Enabled` | User's personal Apple Account | Use the Activation Lock bypass code in Intune (supervised Macs), or ask the user to sign out of Find My. |
| Some values `unknown` | Command output differs on this macOS version | Check the log and the raw command output. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Value reported |

