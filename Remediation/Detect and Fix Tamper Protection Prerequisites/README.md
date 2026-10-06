# Detect and Fix Tamper Protection Prerequisites

An Intune **Remediations** package that makes sure Windows 10 and Windows 11 devices meet the prerequisites for Microsoft Defender **tamper protection**, and fixes the ones a script can fix.

> Tamper protection itself can only be turned on centrally - with an Intune **antivirus policy** (Endpoint security > Antivirus > Windows Security experience profile) or in the **Microsoft Defender portal** - not by a script. Once a device meets the prerequisites, that policy turns tamper protection on at the next check-in.

## Files

| File | Purpose |
|---|---|
| `Detect-TamperProtection.ps1` | Detection script. Exits `1` when a tamper protection prerequisite is missing, `0` when all are met. |
| `Remediate-TamperProtection.ps1` | Remediation script. Runs only when detection exits `1`. Fixes the missing prerequisites it can. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If all prerequisites are met, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which fixes the missing prerequisites it can.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Based on Microsoft's [tamper protection requirements](https://learn.microsoft.com/defender-endpoint/tamper-protection-overview#requirements-for-tamper-protection):

| Check | Reported as |
|---|---|
| Microsoft Defender Antivirus service (`WinDefend`) running | `DefenderServiceNotRunning` |
| No policy turns Defender off (`DisableAntiSpyware` / `DisableAntiVirus` = 1) | `PolicyDisablesDefender:<value>` |
| Real-time protection on | `RealTimeProtectionOff` |
| Cloud-delivered protection (MAPS) on | `CloudProtectionOff` |
| Defender platform **4.18.2010.7** or later | `PlatformTooOld:<version>` |
| Defender engine **1.1.17600.5** or later | `EngineTooOld:<version>` |
| Device onboarded to Microsoft Defender for Endpoint (required to manage tamper protection from Intune or the Defender portal) | `NotOnboardedToDefenderForEndpoint` |

The output also shows `IsTamperProtected` so you can see whether tamper protection is already on. Devices where another antivirus product is active are treated as compliant.

### How each prerequisite is fixed

| Issue | Fix |
|---|---|
| `PolicyDisablesDefender` | Removes the value from `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`. If a **Group Policy** sets it, it comes back at the next policy refresh - fix the GPO too. |
| `DefenderServiceNotRunning` | `Start-Service WinDefend` |
| `RealTimeProtectionOff` | `Set-MpPreference -DisableRealtimeMonitoring $false` |
| `CloudProtectionOff` | `Set-MpPreference -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples` |
| `EngineTooOld` | `MpCmdRun.exe -SignatureUpdate` (engine updates come with signature updates) |
| `PlatformTooOld` | **Skipped.** The platform updates through Windows Update (KB4052623). Install it from Windows Update or the **Detect and Install Windows Updates** remediation. |
| `NotOnboardedToDefenderForEndpoint` | **Skipped.** Onboard the device with an Intune EDR policy (**Endpoint security > Endpoint detection and response**). |

Fixes run in that order: policy values first, then the service, then the settings that need the service. No restart is needed.

Also set **DisableLocalAdminMerge** to true in your Intune antivirus policy - Microsoft lists it as a requirement for managing tamper protection with Intune. It is a policy setting, so this script doesn't change it.

### Skipping checks (optional)

To stop checking something, add its **check name** to `$ExcludeList` at the top of **both** scripts. For example, if you don't use Defender for Endpoint:

```powershell
$ExcludeList = @('NotOnboardedToDefenderForEndpoint')
```

The settings at the top of the two scripts (`$ExcludeList`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- Microsoft Defender Antivirus as the active antivirus.
- Microsoft Defender for Endpoint (P1 or P2) to manage tamper protection from Intune or the Defender portal.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Fix Tamper Protection Prerequisites`
   - **Description**: `Checks and fixes the prerequisites for Microsoft Defender tamper protection (service, policy, real-time and cloud protection, versions, onboarding). Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-TamperProtection.ps1`.
   - **Remediation script file**: upload `Remediate-TamperProtection.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to make these changes).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Fix Tamper Protection Prerequisites**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which prerequisites were missing and whether tamper protection is already on.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TamperProtectionRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check yourself**:
  ```powershell
  Get-MpComputerStatus | Select-Object IsTamperProtected, TamperProtectionSource, RealTimeProtectionEnabled, AMProductVersion, AMEngineVersion
  Get-MpPreference | Select-Object MAPSReporting, SubmitSamplesConsent
  ```
- **A fix doesn't stick**: something else sets the value back - usually a GPO (`gpresult /h report.html`) or another Intune antivirus policy with a different value. Fix it at the source.
- **Prerequisites met but `IsTamperProtected` is False**: turn tamper protection on in your Intune antivirus policy (Windows Security experience profile) or the Defender portal (**Settings > Endpoints > Advanced features > Tamper protection**). It turns on at the next device check-in.
- **Event ID 5013** in the Defender log means tamper protection blocked a change - expected once it is on.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | All tamper protection prerequisites are met, or another antivirus product is active. Remediation does not run. |
| Detection | `1` | One or more prerequisites are missing. Intune runs the remediation script. |
| Remediation | `0` | All prerequisites are met. |
| Remediation | `1` | One or more prerequisites are still missing (platform too old, not onboarded, or a policy sets a value back). See the log. |
