# Detect and Restart Defender Services

An Intune **Remediations** package that finds Microsoft Defender services that have stopped on Windows 10 and Windows 11 devices and starts them again. Intune runs it every 7 days, so a device whose Defender services stopped (after a crash, a failed update or a bad shutdown) is brought back to a protected state on the next run.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderServices.ps1` | Detection script. Exits `1` if a required Defender service is stopped or disabled, `0` if all are running. |
| `Remediate-DefenderServices.ps1` | Remediation script. Runs only when detection exits `1`, and starts every stopped Defender service. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If all required Defender services are running, the device is reported as **Without issues** and nothing else happens.
3. If a service is stopped or disabled, Intune runs the **remediation script**, which starts the stopped services.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### Services checked

| Service name | Display name | Checked when |
|---|---|---|
| `WinDefend` | Microsoft Defender Antivirus Service | Defender is the active antivirus |
| `WdNisSvc` | Microsoft Defender Antivirus Network Inspection Service | Defender is the active antivirus |
| `MDCoreSvc` | Microsoft Defender Core Service | Defender is the active antivirus (only exists on newer Defender platform versions) |
| `Sense` | Windows Defender Advanced Threat Protection Service (Defender for Endpoint) | The device is onboarded to Defender for Endpoint |
| `SecurityHealthService` | Windows Security Service | Always |
| `wscsvc` | Security Center | Always |
| `mpssvc` | Windows Defender Firewall | Always |

A service is reported when it is installed, required on the device, and **not Running** or **Disabled**. Services that aren't installed are ignored.

### Services that are stopped on purpose

These are **not** reported, so healthy devices don't show up as failed:

- **Another antivirus product is active.** When Windows Security Center reports a non-Microsoft antivirus product as turned on, Defender Antivirus steps aside and its services stop by design. `WinDefend`, `WdNisSvc` and `MDCoreSvc` are skipped on those devices.
- **Not onboarded to Defender for Endpoint.** `Sense` only runs on onboarded devices, read from `HKLM\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status\OnboardingState`.
- **Services in `$ExcludeList`.**

### How each service is fixed

| State found | What happens |
|---|---|
| Stopped (start type Automatic or Manual) | `Start-Service`, then wait up to 2 minutes for it to reach Running. |
| Stuck in Start pending / Stop pending | Wait up to 2 minutes for it to settle, then start it if it stopped. |
| **Disabled** | **Skipped and logged.** See below. |

**Running Defender services are never stopped or restarted.** Windows protects them, and Tamper Protection blocks changes, so no script can stop them. The remediation only starts services that have stopped.

**Disabled services can't be re-enabled by a script.** The same protection stops scripts from changing a Defender service's start type. A disabled Defender service usually means:
- a policy turned it off: an Intune antivirus policy, Group Policy, or the registry value `DisableAntiSpyware`,
- or another security product disabled it.

These devices report **Failed** so you can find and fix the cause.

No restart is needed. Each service has a 2-minute limit (`$ServiceTimeoutSeconds`), so the script finishes in well under Intune's 60-minute limit.

### Skipping a service (optional)

To stop checking a service, add its **service name** to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed. For example, if the devices use another firewall:

```powershell
$ExcludeList = @('mpssvc')
```

The two lists must match. Otherwise detection keeps reporting a service that remediation won't start, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Restart Defender Services`
   - **Description**: `Detects stopped Microsoft Defender services and starts them. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-DefenderServices.ps1`.
   - **Remediation script file**: upload `Remediate-DefenderServices.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to start services).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day if you want stopped Defender services caught faster.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Restart Defender Services**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which services were stopped and which were started.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderServicesRemediation.log`. Both scripts log each service found, whether another antivirus product was detected, and whether each service started.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check the services yourself**:
  ```powershell
  Get-Service WinDefend, WdNisSvc, MDCoreSvc, Sense, SecurityHealthService, wscsvc, mpssvc -ErrorAction SilentlyContinue |
      Select-Object Name, DisplayName, Status, StartType
  Get-MpComputerStatus | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AMRunningMode
  ```
- **"Skipped ... service is Disabled"**: check for an Intune antivirus policy or Group Policy that turns off Defender, the `DisableAntiSpyware` registry value under `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`, or another security product. Fix the cause; the next run reports the device as fixed.
- **"Failed to start ... Access is denied"**: Tamper Protection or the service's own protection blocked the start. Check **Windows Security > Virus & threat protection** on the device and the Defender event log (Event Viewer > Applications and Services Logs > Microsoft > Windows > Windows Defender > Operational).
- **"Failed to start ... Time out has expired"**: the service didn't start within 2 minutes. Check the System event log for Service Control Manager errors (event IDs 7000, 7001, 7023, 7031, 7034). A Defender platform update (`Update-MpSignature`, or the latest platform update from Windows Update) or a restart often fixes it.
- **A device with another antivirus shows Defender services as fine**: expected. Defender Antivirus services are skipped when another antivirus product is active.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | All required Defender services are running. Remediation does not run. |
| Detection | `1` | One or more required services are stopped or disabled. Intune runs the remediation script. |
| Remediation | `0` | All required Defender services are running. |
| Remediation | `1` | One or more services are still not running (disabled, access denied or timed out). See the log. |
