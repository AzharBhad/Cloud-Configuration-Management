# Detect and Update Defender Signatures

An Intune **Remediations** package that finds Windows 10 and Windows 11 devices whose Microsoft Defender Antivirus security intelligence (signatures) is out of date and updates it. Out-of-date signatures mean new malware isn't recognized.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderSignatures.ps1` | Detection script. Exits `1` when signatures are older than 24 hours or Defender reports them out of date, `0` when current. |
| `Remediate-DefenderSignatures.ps1` | Remediation script. Runs only when detection exits `1`. Downloads and installs the latest signatures. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If the signatures are current, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which updates the signatures.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

From `Get-MpComputerStatus`, the device is reported when:

- The signatures were last updated more than `$MaxSignatureAgeHours` hours ago (default **24**), or
- Defender itself reports them out of date (`DefenderSignaturesOutOfDate`), or
- The signatures have never been updated.

Devices where another antivirus product is active (reported by Windows Security Center) are treated as compliant, because Defender Antivirus isn't the one protecting them.

### How signatures are updated

| Step | What happens |
|---|---|
| 1. Configured sources | `MpCmdRun.exe -SignatureUpdate` uses the update sources set for the device (Windows Update, WSUS, file share or Microsoft Malware Protection Center), in your policy's order. |
| 2. Fallback | If that fails, `MpCmdRun.exe -SignatureUpdate -MMPC` downloads directly from the Microsoft Malware Protection Center. |
| 3. Confirm | Checks the signatures again with the same rules as the detection script. |

Each attempt is stopped after 15 minutes (`$UpdateTimeoutMinutes`). No restart is needed.

### Skipping devices (optional)

To leave specific devices alone, add their **computer names** to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed. To allow older signatures, change `$MaxSignatureAgeHours` in **both** scripts.

```powershell
$ExcludeList = @('KIOSK-*')
$MaxSignatureAgeHours = 48
```

The settings at the top of the two scripts (`$ExcludeList`, `$MaxSignatureAgeHours`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- Microsoft Defender Antivirus as the active antivirus.
- Devices must be able to reach their update source (Windows Update / WSUS / Microsoft Malware Protection Center).
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Update Defender Signatures`
   - **Description**: `Detects out-of-date Microsoft Defender signatures and updates them. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-DefenderSignatures.ps1`.
   - **Remediation script file**: upload `Remediate-DefenderSignatures.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to make these changes).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day so devices are never more than a day behind.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Update Defender Signatures**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see the signature version and when it was last updated, before and after.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderSignaturesRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check signatures yourself**:
  ```powershell
  Get-MpComputerStatus | Select-Object AntivirusSignatureVersion, AntivirusSignatureLastUpdated, DefenderSignaturesOutOfDate
  ```
- **"still out of date"**: run `"%ProgramFiles%\Windows Defender\MpCmdRun.exe" -SignatureUpdate` on the device and read the error code. Common causes: no internet or proxy blocking `*.update.microsoft.com` / `go.microsoft.com`, WSUS not approving definition updates, or a signature update fallback order policy that leaves out the reachable sources.
- **Defender event log**: Event Viewer > Applications and Services Logs > Microsoft > Windows > Windows Defender > Operational (event IDs 2001 and 2003 are update failures).

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | Signatures are current, or another antivirus product is active. Remediation does not run. |
| Detection | `1` | Signatures are out of date. Intune runs the remediation script. |
| Remediation | `0` | Signatures updated. |
| Remediation | `1` | Signatures could not be updated (no update source reachable, or timed out). See the log. |
