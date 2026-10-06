# Detect and Update Stale Group Policies

An Intune **Remediations** package for **hybrid joined** Windows 10 and Windows 11 devices. It finds devices whose computer Group Policy hasn't been refreshed for more than 24 hours - or whose last refresh failed - and refreshes it with `gpupdate`.

Devices that aren't domain joined are reported as compliant, so it is safe to assign to all devices.

## Files

| File | Purpose |
|---|---|
| `Detect-GroupPolicyRefresh.ps1` | Detection script. Exits `1` when computer Group Policy is stale or failed, `0` when current or not domain joined. |
| `Remediate-GroupPolicyRefresh.ps1` | Remediation script. Runs only when detection exits `1`. Checks a domain controller is reachable, then runs `gpupdate /target:computer /force`. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If Group Policy is current (or the device is not domain joined), the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which refreshes Group Policy.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Windows records the last computer Group Policy refresh in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}` (`EndTimeHi`, `EndTimeLo` and `Status`). The device is reported when:

| Condition | Output |
|---|---|
| Group Policy has never been applied | `Group Policy has never been applied` |
| The last refresh failed (`Status` is not 0) | `Last refresh failed (status N)` |
| The last refresh was more than `$MaxAgeHours` hours ago (default **24**) | `Last refresh was N hours ago` |

Windows normally refreshes computer Group Policy every 90-120 minutes, so a day without a refresh means something is wrong - usually the device hasn't reached a domain controller.

### How it is fixed

| Step | What happens |
|---|---|
| 1. Domain controller | `nltest /dsgetdc:<domain>`. If no domain controller is reachable - for example the device is off the corporate network and not on VPN - it is **skipped**, because Group Policy can't be downloaded. The next run tries again. |
| 2. Refresh | `echo N \| gpupdate /target:computer /force`. The `N` answers any log off / restart prompt. Stopped after 10 minutes. |
| 3. Confirm | Checks again with the same rules as the detection script. |

User Group Policy refreshes on its own at the user's next sign-in or refresh cycle. The device is not restarted, even if a policy asks for one.

### Skipping devices or changing the age limit (optional)

To leave specific devices alone, add their **computer names** to `$ExcludeList` at the top of **both** scripts. To change when Group Policy counts as stale, change `$MaxAgeHours` in **both** scripts.

```powershell
$ExcludeList = @('KIOSK-*')
$MaxAgeHours = 48
```

The settings at the top of the two scripts (`$ExcludeList`, `$MaxAgeHours`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- **Hybrid joined** (domain joined) devices. Other devices are reported as compliant.
- Devices must reach a domain controller (on the corporate network or VPN) for the refresh to work.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Update Stale Group Policies`
   - **Description**: `Refreshes computer Group Policy on hybrid joined devices when it is more than 24 hours old or the last refresh failed. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-GroupPolicyRefresh.ps1`.
   - **Remediation script file**: upload `Remediate-GroupPolicyRefresh.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to make these changes).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day to catch stale policy faster.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Update Stale Group Policies**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see when Group Policy was last refreshed and whether it failed.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\GroupPolicyRefreshRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **"no domain controller ... is reachable"**: the device is off the corporate network or VPN. If it should be able to reach one, check DNS (`nslookup <domain>`) and VPN.
- **"still stale after gpupdate"**: run `gpupdate /target:computer /force` on the device and read the error, and check the GroupPolicy event log (Event Viewer > Applications and Services Logs > Microsoft > Windows > GroupPolicy > Operational). `gpresult /h report.html` shows which policies applied and which failed.
- **Last refresh status codes**: `1355` = domain doesn't exist or can't be contacted, `1722` = RPC server unavailable (network or firewall), `1058` = a GPO file couldn't be read from SYSVOL.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | Group Policy is current, or the device is not domain joined. Remediation does not run. |
| Detection | `1` | Group Policy is stale or the last refresh failed. Intune runs the remediation script. |
| Remediation | `0` | Group Policy refreshed. |
| Remediation | `1` | No domain controller reachable, or the refresh failed. See the log. |
