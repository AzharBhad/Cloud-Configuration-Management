# Detect and Remove Unauthorized Local Admins

An Intune **Remediations** package that finds unauthorized members of the local **Administrators** group on Windows 10 and Windows 11 devices and removes them. The accounts are not deleted - they only lose administrator rights.

**Read the Microsoft Entra section below before deploying.** The allowed list must contain your tenant's Entra role SIDs, or the script keeps Entra accounts for safety and reports the device as **Failed**.

## Files

| File | Purpose |
|---|---|
| `Detect-LocalAdmins.ps1` | Detection script. Exits `1` when the Administrators group has a member not in `$ExcludeList`, `0` when only allowed members. |
| `Remediate-LocalAdmins.ps1` | Remediation script. Runs only when detection exits `1`. Removes unauthorized members, with safety rules so admin access to the device isn't lost. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If the Administrators group only contains allowed members, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which removes the unauthorized members.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Every member of the local Administrators group is compared with `$ExcludeList` (the **allowed members**), matched on SID or `DOMAIN\Name`. The group is found by its well-known SID (`S-1-5-32-544`), so it works on every Windows language, and members are read with ADSI so orphaned SIDs of deleted accounts are included.

Allowed by default:

| Member | SID pattern | Why |
|---|---|---|
| Built-in local Administrator | `S-1-5-21-*-500` | Used by Windows LAPS; disabled by default |
| Domain Admins | `S-1-5-21-*-512` | Hybrid joined devices |

### Microsoft Entra joined devices

On Entra joined devices, Windows adds two **Entra role** SIDs to the Administrators group: **Global Administrator** and **Microsoft Entra Joined Device Local Administrator**. The user who joined the device may also have been added. All of them look like `S-1-12-1-...`, so a script can't tell a role from a user.

To stop it removing your admin roles by mistake, the script **keeps** every `S-1-12-1-...` SID not in `$ExcludeList` while `$ProtectUnknownEntraSids` is `$true` (the default). They are reported as unauthorized but not removed, and the device shows **Failed**.

To finish setting it up:

1. Find the **directory object IDs** of the two roles in your tenant with Microsoft Graph PowerShell: `Get-MgDirectoryRole | Select-Object DisplayName, Id`. Use these `Id` values, not the role template IDs - the template IDs are the same in every tenant and won't match the SIDs on your devices.
2. Convert each object ID to a SID with this PowerShell function:
   ```powershell
   function ConvertTo-EntraSid ([guid]$ObjectId) {
       $bytes = $ObjectId.ToByteArray()
       $parts = 0..3 | ForEach-Object { [BitConverter]::ToUInt32($bytes, $_ * 4) }
       'S-1-12-1-' + ($parts -join '-')
   }
   ConvertTo-EntraSid '<role object Id from step 1>'
   ```
   You can also run `whoami /groups` as a Global Administrator on an Entra joined device and copy the `S-1-12-1-...` SIDs.
3. Add both SIDs to `$ExcludeList` in **both** scripts, and set `$ProtectUnknownEntraSids = $false` in **both** scripts. From then on, any other Entra user in the group - such as the user who joined the device - is removed.

### How members are removed

Each unauthorized member is removed with `Remove-LocalGroupMember`; if that fails (it can for orphaned SIDs), ADSI is used instead. The change applies at the user's next sign-in.

| Safety rule | What happens |
|---|---|
| Unknown Entra SIDs while `$ProtectUnknownEntraSids` is `$true` | Kept and reported as Protected. |
| Removing would leave no allowed member other than the built-in Administrator | **Nothing is removed**, so the device always keeps a working admin. Add the right accounts or groups to `$ExcludeList`. |

To give a user admin rights properly, use Intune **Endpoint security > Account protection > Local user group membership**, or Windows LAPS for the built-in Administrator account, and add those to `$ExcludeList`.

### Allowing more members (optional)

Add SIDs or `DOMAIN\Name` values (wildcards allowed) to `$ExcludeList` at the top of **both** scripts. SIDs are safer than names because names can be renamed.

```powershell
$ExcludeList = @(
    'S-1-5-21-*-500'                                          # Built-in Administrator (LAPS)
    'S-1-5-21-*-512'                                          # Domain Admins
    'S-1-12-1-1111111111-2222222222-3333333333-4444444444'    # Global Administrator role
    'S-1-12-1-5555555555-6666666666-7777777777-8888888888'    # Entra Joined Device Local Administrator role
    'CONTOSO\Workstation Admins'                              # A domain group
)
$ProtectUnknownEntraSids = $false
```

The settings at the top of the two scripts (`$ExcludeList`, `$ProtectUnknownEntraSids`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- Your Microsoft Entra role SIDs added to `$ExcludeList` (see above) for Entra joined devices.
- Recommended: **Windows LAPS** for the built-in Administrator account, so there is always a managed way to get admin access to a device.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Remove Unauthorized Local Admins`
   - **Description**: `Finds members of the local Administrators group that are not on the allowed list and removes them, with safety rules. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-LocalAdmins.ps1`.
   - **Remediation script file**: upload `Remediate-LocalAdmins.ps1`.
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

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Remove Unauthorized Local Admins**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see every unauthorized member (name and SID) and what happened to it.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminsRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check the group yourself**: `net localgroup Administrators`, or for SIDs:
  ```powershell
  ([ADSI]'WinNT://./Administrators,group').psbase.Invoke('Members') | ForEach-Object {
      (New-Object Security.Principal.SecurityIdentifier($_.GetType().InvokeMember('objectSid','GetProperty',$null,$_,$null),0)).Value }
  ```
- **Devices stay "Failed" with "kept unknown Entra SIDs"**: add your Entra role SIDs to `$ExcludeList` and set `$ProtectUnknownEntraSids = $false`, as described above.
- **"Safety stop"**: removing members would have left no admin. Add an approved admin account or group to `$ExcludeList`.
- **A removed user is added back**: something adds them again - an Intune account protection policy, a Group Policy (Restricted Groups or Local Users and Groups preferences), or the user's own admin tools. Align that policy with `$ExcludeList`.
- **A user still has admin rights after removal**: the change applies at their next sign-in.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | The Administrators group only contains allowed members. Remediation does not run. |
| Detection | `1` | Unauthorized members were found. Intune runs the remediation script. |
| Remediation | `0` | All unauthorized members removed. |
| Remediation | `1` | Members were kept for safety (unknown Entra SIDs, or the safety stop) or a removal failed. See the log. |
