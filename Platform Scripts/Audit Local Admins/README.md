# Audit Local Admins

An Intune **platform script** that audits the local **Administrators** group on Windows 10 and Windows 11 devices and writes a report for remediation teams.

Why use it:

- **Finds devices with multiple local admin accounts.** Flags devices with more enabled admin user accounts than allowed (default: more than 1).
- **Detects policy violations.** Flags members that aren't on your approved list, local accounts with admin rights, and domain users added directly instead of through a group.
- **Detects privileged access risks.** Flags admin accounts without a password, passwords that never expire or haven't changed in 90 days, orphaned SIDs of deleted accounts, and an enabled built-in Administrator.
- **Creates reports for remediation teams.** Writes a CSV (one row per member) and a JSON summary (device, findings, risk level) on each device. It can also copy them to a file share, and writes an event to the Application event log for log collection tools.

**The script is read-only.** It never adds, removes or changes accounts or group membership. To remove unapproved admins automatically, use the **Detect and Remove Unauthorized Local Admins** remediation in `Remediation/`.

## Files

| File | Purpose |
|---|---|
| `Invoke-LocalAdminAudit.ps1` | The platform script you upload to Intune. |
| `README.md` | This document. |

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **Security review or audit** | One-time snapshot of who has admin rights on every device, with a risk level per device. |
| **Before turning on automatic removal** | Run the audit first to see who would be removed, then fill in the approved list before deploying the **Detect and Remove Unauthorized Local Admins** remediation. |
| **After a migration or merger** | Finds leftover local accounts, old domain users and orphaned SIDs from the previous environment. |
| **After an incident** | Quickly checks a group of devices for unexpected admin accounts. |
| **Compliance evidence** | CSV/JSON reports show least-privilege controls for ISO 27001, SOC 2, Cyber Essentials and similar standards. |

> A platform script runs **once** per device. For an audit that repeats on a schedule, deploy the same checks as an Intune **Remediation** with a detection script only (see `/new-remediation`). The admin center then shows each device's latest result.

### What the script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit. | Already 64-bit. |
| 2 | List members | Reads every member of the Administrators group with ADSI. The group is found by its well-known SID `S-1-5-32-544`, so it works on every Windows language, and orphaned SIDs are included. | - |
| 3 | Member details | Records name, SID, type (User / Group), source (Local, Domain, EntraID, BuiltIn) and approval. For local accounts it also records enabled state, password required, password never expires and password last set. | Local details are skipped for non-local members. |
| 4 | Find issues | Checks each member and the device against the findings below. | Finding codes in `$ExcludeList`. |
| 5 | Write reports | Writes `LocalAdminAudit-<computer>-<time>.csv` and `.json`, plus `LocalAdminAudit-Latest.csv` / `.json`, to `$ReportFolder`. The folder is locked to SYSTEM and Administrators. Keeps the newest `$KeepReports` reports. | - |
| 6 | Copy to share | Copies the CSV and JSON to `$ReportShare`, stopping after `$ShareCopyTimeoutSeconds`. | `$ReportShare` is empty (default). |
| 7 | Event log | Writes event **1000** (Information, no findings) or **1001** (Warning, findings) to the Application log, source `IntuneLocalAdminAudit`. | - |
| 8 | Result | Writes one summary line and exits. The device shows as **Failed** in Intune when findings were found (see `$ReportFindingsAsFailure`). | - |

### Findings

| Code | Severity | Meaning |
|---|---|---|
| `UnapprovedMember` | High | Member not in `$ApprovedMembers`. |
| `MultipleAdminAccounts` | High | More than `$MaxAdminAccounts` **enabled admin user accounts** on the device. Counted: enabled local users, plus domain and Entra user accounts. Groups and disabled local accounts are not counted. |
| `LocalAccountNoPassword` | High | Enabled local admin account that doesn't require a password. |
| `OrphanedSid` | Medium | SID of a deleted account that is still in the group. |
| `LocalAdminAccount` | Medium | Local user account (other than the built-in Administrator) with admin rights - not covered by Entra ID sign-in controls such as MFA. |
| `PasswordNeverExpires` | Medium | Enabled local admin account whose password never expires. |
| `StalePassword` | Medium | Enabled local admin account whose password is older than `$MaxPasswordAgeDays` days. |
| `DirectDomainUser` | Low | Domain user added directly instead of through a group. |
| `BuiltInAdminEnabled` | Low | Built-in Administrator account is enabled. Turn off with `$FlagBuiltInAdminEnabled = $false` if Windows LAPS manages it. |

The device's **risk level** is the highest severity found: **High**, **Medium**, **Low** or **None**.

### The report

**CSV** - one row per Administrators group member:

| Column | Example |
|---|---|
| `ComputerName`, `AuditTime` | `PC-0142`, `2026-10-07T09:15:02` |
| `Name`, `Sid` | `PC-0142\helpdesk`, `S-1-5-21-...-1001` |
| `Class`, `Source` | `User`, `Local` |
| `Resolved`, `Approved` | `True`, `False` |
| `Enabled`, `PasswordRequired`, `PasswordNeverExpires`, `PasswordLastSet` | `True`, `True`, `True`, `2025-11-02T08:00:00` (local accounts only) |
| `Findings` | `UnapprovedMember;LocalAdminAccount;PasswordNeverExpires;StalePassword` |

**JSON** - the device (name, serial number, OS, domain, Entra / domain join state), member count, admin account count, risk level, every finding with its severity and member, and all member details.

To combine the reports from many devices, copy them to a share (`$ReportShare`) and open them in Excel, or run `Get-ChildItem \\server\share\*.csv | Import-Csv | Export-Csv All.csv -NoTypeInformation`.

## Settings in the script

At the top of `Invoke-LocalAdminAudit.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$ApprovedMembers` | Built-in Administrator (`S-1-5-21-*-500`), Domain Admins (`S-1-5-21-*-512`) | Approved members, matched on SID or `DOMAIN\Name`, wildcards allowed. Add your Entra role SIDs (below) and admin groups. |
| `$MaxAdminAccounts` | `1` | More enabled admin user accounts than this = `MultipleAdminAccounts`. |
| `$MaxPasswordAgeDays` | `90` | Local admin passwords older than this = `StalePassword`. |
| `$FlagBuiltInAdminEnabled` | `$true` | Flag an enabled built-in Administrator. Set to `$false` if Windows LAPS manages it. |
| `$ExcludeList` | `@()` | Finding codes to ignore (wildcards allowed). |
| `$ReportFolder` | `C:\ProgramData\IntuneAudit\LocalAdmins` | Where reports are written on the device. |
| `$KeepReports` | `10` | How many reports to keep on the device. |
| `$ReportShare` | `''` (off) | File share to copy reports to, for example `\\fileserver\LocalAdminAudit$`. |
| `$ShareCopyTimeoutSeconds` | `120` | Time limit for the share copy. |
| `$EventSource` | `IntuneLocalAdminAudit` | Application event log source. |
| `$ReportFindingsAsFailure` | `$true` | Show devices with findings as **Failed** in Intune. Set to `$false` to show every completed audit as **Success**. |

Example:

```powershell
$ApprovedMembers = @(
    'S-1-5-21-*-500'                                          # Built-in Administrator (LAPS)
    'S-1-5-21-*-512'                                          # Domain Admins
    'S-1-12-1-1111111111-2222222222-3333333333-4444444444'    # Global Administrator role
    'S-1-12-1-5555555555-6666666666-7777777777-8888888888'    # Entra Joined Device Local Administrator role
    'CONTOSO\Workstation Admins'                              # A domain group
)
$MaxAdminAccounts = 2
$FlagBuiltInAdminEnabled = $false
$ExcludeList = @('DirectDomainUser')
$ReportShare = '\\fileserver\LocalAdminAudit$'
```

### Microsoft Entra role SIDs

On Entra joined devices, Windows adds the **Global Administrator** and **Microsoft Entra Joined Device Local Administrator** roles to the Administrators group as `S-1-12-1-...` SIDs. Add them to `$ApprovedMembers`, or they are reported as `UnapprovedMember` on every device. Some devices may also report them as user accounts, which counts them toward `MultipleAdminAccounts`. Check the `Class` column in the report and raise `$MaxAdminAccounts` if needed.

1. Find the **directory object IDs** of the two roles in your tenant with Microsoft Graph PowerShell: `Get-MgDirectoryRole | Select-Object DisplayName, Id`. Use these `Id` values, not the role template IDs.
2. Convert each ID to a SID:
   ```powershell
   function ConvertTo-EntraSid ([guid]$ObjectId) {
       $bytes = $ObjectId.ToByteArray()
       $parts = 0..3 | ForEach-Object { [BitConverter]::ToUInt32($bytes, $_ * 4) }
       'S-1-12-1-' + ($parts -join '-')
   }
   ConvertTo-EntraSid '<role object Id from step 1>'
   ```
   You can also run `whoami /groups` as a Global Administrator on an Entra joined device and copy the `S-1-12-1-...` SIDs.

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | One audit snapshot per device. Re-run it (below) for a fresh audit, or use a detection-only Remediation for repeated audits. |
| **Re-runs after you change the script** | Changing a setting (for example `$ApprovedMembers`) and uploading again produces a new audit on every device. Safe - the script only reads and writes reports. |
| **Re-runs for every new user** who signs in (device assignment) | A new report is written each time. Old reports are cleaned up after `$KeepReports`. |
| **Retries 3 times** after a failure | With `$ReportFindingsAsFailure = $true`, a device with findings counts as failed, so it is audited again at the next three check-ins. That is harmless and gives fresh reports. |
| **30-minute time limit** | The audit takes seconds. The share copy is limited to `$ShareCopyTimeoutSeconds`. |
| **Runs before Win32 apps** | Admin accounts created later by app installs only show up in a later audit. |

## Prerequisites

- **Windows 10 or Windows 11** (Pro, Enterprise or Education).
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- For hybrid joined devices: network access to a domain controller, so domain account names can be resolved. Without it, members still appear by SID.
- For `$ReportShare`: a share where the **computer account** (for example **Domain Computers**) can write. Entra-only joined devices usually can't write to on-premises shares; collect their reports through the event log instead (see *Check the results*).
- An Intune role that can add platform scripts, such as **Intune Administrator** or **Policy and Profile Manager**.

## Step-by-step: add the script in Intune

1. Edit the settings at the top of `Invoke-LocalAdminAudit.ps1` - at least `$ApprovedMembers` (see above).
2. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
3. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
4. **Basics**
   - **Name**: `Audit Local Admins`
   - **Description**: `Read-only audit of the local Administrators group. Reports multiple admin accounts, policy violations and privileged access risks.`
   - Select **Next**.
5. **Script settings**
   - **Script location**: browse to `Invoke-LocalAdminAudit.ps1`.
   - **Run this script using the logged on credentials**: **No**. The script must run as **SYSTEM**: reading account details, writing the protected report folder and writing to the event log need admin rights.
   - **Enforce script signature check**: **No** (unless you sign the script).
   - **Run script in 64-bit PowerShell host**: **Yes**. (The script also relaunches itself in 64-bit if left at No.)
   - Select **Next**.
6. **Scope tags**: choose scope tags if you use them, then select **Next**.
7. **Assignments**
   - Under **Included groups**, select a **device group**, for example all Windows 10/11 corporate devices. The audit is about the device, so assign to devices, not users. Start with a small **pilot group**.
   - Select **Next**.
8. **Review + add**: check the settings and select **Add**.

## Step-by-step: check the results

1. Go to **Devices > Scripts and remediations > Platform scripts** and open **Audit Local Admins**.
2. Open **Device status**:
   - **Success** - audit completed with no findings (or `$ReportFindingsAsFailure` is `$false`).
   - **Failed** - findings were found (or the audit itself failed). This is your list of devices to look at.
3. Read a device's summary line: Intune stores it as the script's **result message**. It is available through Microsoft Graph (beta): `deviceManagement/deviceManagementScripts/{id}/deviceRunStates`, property `resultMessage`.
4. Get the full report for a device:
   - On the device: `C:\ProgramData\IntuneAudit\LocalAdmins\LocalAdminAudit-Latest.csv` (admins only).
   - On the share, if `$ReportShare` is set.
   - Through your log collection: **Application** event log, source `IntuneLocalAdminAudit`, event **1001**. Azure Monitor Agent (Log Analytics) or your SIEM can collect it from every device.
5. Hand the report to the remediation team. Fix the findings by hand, or with the **Detect and Remove Unauthorized Local Admins** remediation once `$ApprovedMembers` is right.

Check a device yourself:

```powershell
Import-Csv C:\ProgramData\IntuneAudit\LocalAdmins\LocalAdminAudit-Latest.csv | Format-Table Name, Source, Class, Enabled, Findings
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'IntuneLocalAdminAudit' } -MaxEvents 5
```

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment or a setting), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device.
- **For specific devices:** remove them from the assigned group, wait for the next check-in, then add them back. Or assign the script to a new group containing just those devices.
- **New users:** a device-assigned script runs again when a new user signs in, which writes a new report.

## Undo

The audit changes nothing on the device except its own files. To remove them:

```powershell
Remove-Item -Recurse -Force C:\ProgramData\IntuneAudit\LocalAdmins
Remove-EventLog -Source IntuneLocalAdminAudit
```

Remove the script's assignment first, or it may run again.

## Troubleshooting

- **Script log on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminAuditPlatformScript.log` lists every member, its findings, the report paths and any share or event log problems.
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`:
  - `IntuneManagementExtension.log` - when the script was received and run, and its result.
  - `AgentExecutor.log` - the PowerShell run itself, including exit code and any error output.

| Problem | Cause and fix |
|---|---|
| Every device shows **Failed** | Usually Entra role SIDs or your admin groups aren't in `$ApprovedMembers`, so every device reports `UnapprovedMember`. Read one report, add the right SIDs/groups, and upload again. |
| `MultipleAdminAccounts` on every device | Entra role SIDs counted as user accounts, or a legitimate second admin account. Check the `Class` column, then raise `$MaxAdminAccounts` or remove the extra account. |
| Members show only as SIDs (`OrphanedSid`) | The account was deleted - remove the SID from the group. On hybrid joined devices it can also mean no domain controller was reachable to resolve the name; re-run on the corporate network or VPN. |
| `Copy to ... failed` / `timed out` in the log | The computer account can't write to `$ReportShare`, or the share isn't reachable. Check share and NTFS permissions for **Domain Computers**. Local reports are still written. |
| `Could not write to the event log` | Rare; the event log service or source registration failed. Reports are still written. |
| Script shows **Failed** but the report has no findings | The audit itself failed. Check the script log and `AgentExecutor.log`. |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec):

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Invoke-LocalAdminAudit.ps1
```

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | Audit completed with no findings, or with findings and `$ReportFindingsAsFailure = $false`. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | Audit completed **with findings** (`$ReportFindingsAsFailure = $true`), or the audit failed. See the report and log. | Reports **Failed** and runs it again at the next three check-ins. |
