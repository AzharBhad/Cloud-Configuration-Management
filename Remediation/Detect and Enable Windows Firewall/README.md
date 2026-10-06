# Detect and Enable Windows Firewall

An Intune **Remediations** package that finds Windows 10 and Windows 11 devices where Windows Defender Firewall is turned off - for any profile, or because its service is stopped - and turns it back on.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsFirewall.ps1` | Detection script. Exits `1` when any firewall profile is off or the firewall service is not running, `0` when everything is on. |
| `Remediate-WindowsFirewall.ps1` | Remediation script. Runs only when detection exits `1`. Starts the firewall service and turns the profiles back on. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If the firewall is on for every profile and its service is running, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which turns the firewall back on.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

| Check | Output |
|---|---|
| **Domain**, **Private** and **Public** profiles in the effective (active) firewall settings | `Profile <name>: off` |
| Windows Defender Firewall service (`mpssvc`) running and not disabled | `Service mpssvc: <status>, <start type>` |

The active settings combine local settings, Group Policy and Intune, so this shows what is actually enforced on the device.

### How it is fixed

| Step | What happens |
|---|---|
| 1. Service | If `mpssvc` is disabled, sets it to Automatic; then starts it. Windows protects this service, so this may be refused - that is logged. |
| 2. Profiles | For each profile that is off: if **Group Policy** (`HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\<Profile>Profile`) or **Intune** (`...\FirewallPolicy\Mdm\<Profile>Profile`) sets `EnableFirewall = 0`, the profile is **skipped** - changing the local setting would have no effect because the policy wins. Otherwise `Set-NetFirewallProfile -Enabled True`. |
| 3. Confirm | Checks again with the same rules as the detection script. |

Firewall rules are not changed. No restart is needed.

### Skipping profiles (optional)

To stop checking a profile, add its name (`Domain`, `Private` or `Public`) to `$ExcludeList` at the top of **both** scripts.

```powershell
$ExcludeList = @('Domain')
```

The settings at the top of the two scripts (`$ExcludeList`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Enable Windows Firewall`
   - **Description**: `Detects a disabled Windows Defender Firewall (any profile, or a stopped service) and turns it back on. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-WindowsFirewall.ps1`.
   - **Remediation script file**: upload `Remediate-WindowsFirewall.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to make these changes).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day if you want a disabled firewall caught faster.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Enable Windows Firewall**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which profiles were off and whether the service was running.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsFirewallRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check the firewall yourself**:
  ```powershell
  Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name, Enabled
  Get-Service mpssvc
  ```
- **"Skipped profile ...: Group Policy turns it off"** or **"Intune (MDM) turns it off"**: a policy deliberately turns the firewall off. Find it with `gpresult /h report.html` or in Intune (**Endpoint security > Firewall**, and **Devices > Configuration** profiles), and change it.
- **Third-party firewall**: if another firewall product manages the device, it may turn Windows Firewall off on purpose. Add the profiles to `$ExcludeList` or exclude those devices from the assignment.
- **"Could not repair the mpssvc service"**: check the System event log for Service Control Manager errors (event IDs 7000, 7023, 7031).

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | The firewall is on for all checked profiles and the service is running. Remediation does not run. |
| Detection | `1` | A profile is off or the service is not running. Intune runs the remediation script. |
| Remediation | `0` | The firewall is on for all checked profiles and the service is running. |
| Remediation | `1` | Something is still off - usually a policy turns it off. See the log. |
