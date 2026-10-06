# Detect and Restore Registry Security Settings

An Intune **Remediations** package that checks a set of required registry security settings on Windows 10 and Windows 11 devices and restores any that are missing or have been changed.

The default baseline hardens credential handling and turns off legacy protocols. **Review it against your own security standard before deploying** - edit `$Baseline` at the top of both scripts.

## Files

| File | Purpose |
|---|---|
| `Detect-RegistrySecurity.ps1` | Detection script. Exits `1` when any setting in `$Baseline` is missing or different, `0` when all match. |
| `Remediate-RegistrySecurity.ps1` | Remediation script. Runs only when detection exits `1`. Writes the required value for each setting that differs. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If all settings match the baseline, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which restores the settings.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### Default baseline

| Id | Registry value | Required | Restart | Why |
|---|---|---|---|---|
| `NTLMv2Only` | `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LmCompatibilityLevel` | `5` | No | Send NTLMv2 only; refuse LM and NTLM |
| `NoLMHash` | `...\Control\Lsa\NoLMHash` | `1` | No | Don't store LAN Manager password hashes |
| `RestrictAnonymous` | `...\Control\Lsa\RestrictAnonymous` | `1` | No | No anonymous listing of shares |
| `RestrictAnonymousSAM` | `...\Control\Lsa\RestrictAnonymousSAM` | `1` | No | No anonymous listing of accounts |
| `LsaRunAsPPL` | `...\Control\Lsa\RunAsPPL` | `1` | **Yes** | Run LSA as a protected process (credential theft protection) |
| `WDigestOff` | `...\Control\SecurityProviders\WDigest\UseLogonCredential` | `0` | No | Don't keep plain-text passwords in memory |
| `SMBv1ServerOff` | `HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1` | `0` | **Yes** | Turn off the SMBv1 server |
| `AutoRunOff` | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun` | `255` | No | Turn off AutoRun for all drives |
| `UACOn` | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA` | `1` | **Yes** | User Account Control on |
| `LLMNROff` | `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast` | `0` | No | Turn off LLMNR (name spoofing protection) |

A setting is reported when its value is missing or different.

**Before turning on `NTLMv2Only`, `LsaRunAsPPL` and `SMBv1ServerOff`**, check for old systems that need NTLM/LM, old SMBv1 file shares, or LSA plug-ins and drivers that aren't signed for protected mode. Test on a pilot group first.

### How settings are restored

For each setting that differs, the script creates the registry key if it is missing and writes the required value (`New-ItemProperty -Force`), then checks everything again.

Settings marked **Restart: Yes** take effect after the next restart. The script never restarts the device; the output lists the settings waiting for a restart.

If **Group Policy or Intune** sets one of these values differently, it is changed back at the next policy refresh and the device is reported again. Fix the conflicting policy, or add the setting to `$ExcludeList`.

### Skipping or adding settings (optional)

To skip a setting, add its **Id** or its `<Path>\<Name>` to `$ExcludeList` at the top of **both** scripts. To add a setting, add a line to `$Baseline` in **both** scripts:

```powershell
$ExcludeList = @('LsaRunAsPPL')

# Added to $Baseline:
@{ Id = 'SMBClientSigning'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name = 'RequireSecuritySignature'; Type = 'DWord'; Value = 1; Reboot = $false
   Description = 'Require SMB client signing' }
```

The settings at the top of the two scripts (`$ExcludeList`, `$Baseline`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Restore Registry Security Settings`
   - **Description**: `Restores required registry security settings (NTLMv2 only, LSA protection, WDigest, SMBv1, AutoRun, UAC, LLMNR) when they are missing or changed. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-RegistrySecurity.ps1`.
   - **Remediation script file**: upload `Remediate-RegistrySecurity.ps1`.
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

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Restore Registry Security Settings**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which settings differed, their old values, and which need a restart.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RegistrySecurityRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **The same setting is reported on every run**: a Group Policy or Intune policy sets it back. Find it with `gpresult /h report.html` or in Intune, and fix it there, or add the setting to `$ExcludeList`.
- **An app or file share stopped working after deployment**: the most likely causes are `NTLMv2Only` (old servers or NAS devices that need NTLM), `SMBv1ServerOff` (old devices that connect to this PC with SMBv1) and `LsaRunAsPPL` (unsigned LSA plug-ins). Add the setting to `$ExcludeList` and plan the fix.
- **Check a value yourself**: `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' | Select-Object LmCompatibilityLevel, RunAsPPL, NoLMHash`.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | All settings match the baseline. Remediation does not run. |
| Detection | `1` | One or more settings are missing or different. Intune runs the remediation script. |
| Remediation | `0` | All settings now match the baseline (a restart may still be needed). |
| Remediation | `1` | One or more settings could not be written. See the log. |
