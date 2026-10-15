# Report FileVault Status (macOS custom attribute)

An Intune **custom attribute** that reports each Mac's **FileVault** state as one line: whether encryption is on, still running, or deferred until the next sign-in, and whether a **personal recovery key (PRK)** exists to escrow. Read-only.

**Why a script:** The FileVault configuration profile **enables** encryption and escrows the key, but Macs stuck in *deferred* or *in progress*, or with no PRK, are hard to spot. A custom attribute shows the state per device in the admin center every 8 hours. A one-off script would only report once.

## Files

| File | Purpose |
|---|---|
| `report-filevault-status.sh` | The script you upload to Intune as a **custom attribute**. |
| `README.md` | This document. |

## Typical actions

### When to use it

| Scenario | Why this script helps |
|---|---|
| Encryption rollout | Track Macs that haven't finished encrypting, or are waiting for the user to sign out and in. |
| Recovery readiness | Find Macs without a personal recovery key. Compare with **Devices > [Mac] > Recovery keys**. |
| Compliance follow-up | Explain why a Mac fails the FileVault compliance setting. |

### What the script does on the Mac

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | Status | `fdesetup status` mapped to On / Off / Encrypting / Decrypting / Deferred | - |
| 2 | Recovery key | `fdesetup haspersonalrecoverykey` (true/false) | - |
| 3 | Deferral | `fdesetup showdeferralinfo`: is enablement waiting for a user? | - |
| 4 | Report | Echoes `Status=…; PRK=…; Deferred=…`. Only this goes to stdout. | - |

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
   - **Name**: `macOS - FileVault Status`
   - **Description**: Reports FileVault state, personal recovery key presence and deferral.
4. **Attribute settings**:
   - **Data type of attribute**: **String**. The script echoes one text line.
   - **Script**: upload `report-filevault-status.sh`.
5. **Assignments**: start with a **pilot device group**, then all corporate Macs. Device groups are recommended; with user groups the attribute runs on any Mac the user signs in to.
6. **Review + add**: select **Add**.

## Step-by-step: check the results

1. Go to **Devices > By platform > macOS > Organize devices > Custom attributes for macOS > macOS - FileVault Status > Device status**.
2. The **Result** column shows the value per Mac, for example `Status=On; PRK=true; Deferred=false`.
3. Export the list (CSV) and filter for the values that need action (see "Typical actions").
4. On a Mac, check the details with `sudo cat "/Library/Logs/Microsoft/IntuneScripts/ReportFileVaultStatus/ReportFileVaultStatus.log"`.

## Running it again

Custom attributes re-run automatically every 8 hours. Upload a changed script to change what is reported.

## Undo

Nothing to undo (read-only). Delete the custom attribute to stop reporting.

## Troubleshooting

- **Script log**: `/Library/Logs/Microsoft/IntuneScripts/ReportFileVaultStatus/ReportFileVaultStatus.log` (rolled over above 1 MB to `.log.1`).
- **Intune agent logs**: `/Library/Logs/Microsoft/Intune/`. Check that the agent exists at `/Library/Intune/Microsoft Intune Agent.app`.
- **Test locally** on a test Mac: `sudo bash ./report-filevault-status.sh`, then read the log.
- **Script not running**: wait for the 8-hour agent check-in, or select **Check settings** in Company Portal. Check the Mac has no proxy.

| Symptom | Cause | Resolution |
|---|---|---|
| `Status=Deferred` | FileVault waits for the user's next sign-out and sign-in | Ask the user to sign out and in, or restart. |
| `PRK=false` with `Status=On` | Encrypted without a PRK (for example before the profile) | Rotate or issue a PRK through the FileVault profile and Intune recovery key rotation. |
| `Status=Unknown` | Unexpected `fdesetup` output | Check the log for the raw output. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Value reported |
| 1 | `fdesetup` not available |

