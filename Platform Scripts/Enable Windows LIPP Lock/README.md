# Enable Windows LIPP Lock

An Intune **platform script** that locks Windows 10 and Windows 11 devices that haven't been used for **14 consecutive days**:

- **Logs off all users** from the device when it has been idle for 14 days in a row.
- **Puts the device in the non-compliant state** in Intune, through a custom compliance policy, so Conditional Access can block it from company resources until IT reviews it.

Why use it: a device nobody has used for two weeks may be lost, stolen, left in a drawer or no longer needed. Signing everyone out closes open sessions, and marking it non-compliant stops it reaching company data until someone confirms it is still in the right hands.

## Files

| File | Purpose |
|---|---|
| `Install-IdleDeviceLock.ps1` | The platform script you upload to Intune. It contains the daily checker it installs on the device. |
| `README.md` | This document - including the custom compliance discovery script and JSON rules to create in Intune. |

## How it works

A platform script runs only **once**, so it can't watch for 14 idle days by itself, and a device can't set its own Intune compliance state. The solution has two parts:

| Part | What it is | What it does |
|---|---|---|
| **1. This platform script** | Runs once per device | Installs a checker script in `C:\ProgramData\IntuneIdleDeviceLock` and a scheduled task, **Intune Idle Device Lock**, that runs it as SYSTEM **every day at 09:00 and at every startup**. |
| **2. The daily checker** (installed by part 1) | Runs every day | Works out how long the device has been idle. At 14 days it **logs off every user** and sets the lock flag `Locked = 1` in `HKLM\SOFTWARE\IntuneIdleDeviceLock`. |
| **3. A custom compliance policy** (you create it - see below) | Runs with every compliance check | Its discovery script reads the lock flag. While `Locked = 1`, Intune marks the device **non-compliant**. |

### How "idle" is measured

The checker takes the **most recent** of:

| Sign of use | Where it comes from |
|---|---|
| The last keyboard/mouse input in any signed-in or disconnected session | `quser` (IDLE TIME of each session) |
| The last time any user profile was used (signed in or out) | `Win32_UserProfile.LastUseTime` |
| The time the lock was installed | `HKLM\SOFTWARE\IntuneIdleDeviceLock\InstalledOn` - so no device is ever locked within 14 days of deploying this script |

The device is **idle** when that time is 14 or more days ago. Days the device is switched off count as idle: a device that was off for two weeks is locked at its next startup (the task runs at startup, before anyone signs in).

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **Lost or stolen device detection** | A device that goes silent for two weeks is cut off from company data automatically. |
| **Unused or forgotten devices** | Finds devices in drawers and spare stock; IT reviews them before they are used again. |
| **Leavers and long absences** | Devices of people who stopped working are signed out and blocked until reissued. |
| **Shared and kiosk-style devices** | Old sessions don't stay signed in indefinitely. |
| **Security baseline / audit** | Shows inactive devices are controlled, for ISO 27001 / Cyber Essentials style requirements. |

### What the platform script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit. | Already 64-bit. |
| 2 | Exclusions | If the computer name matches `$ExcludeList`, **removes** the task, checker and lock flag, and stops. | Name not in the list. |
| 3 | Install folder | Creates `C:\ProgramData\IntuneIdleDeviceLock`, readable and writable **only by SYSTEM and Administrators** - the checker runs as SYSTEM, so users must not be able to change it. | - |
| 4 | Checker | Writes `Invoke-IdleDeviceCheck.ps1` into the folder. | Already there and unchanged. |
| 5 | Scheduled task | Registers **Intune Idle Device Lock**: daily at `$CheckTime` and at startup, as SYSTEM, catches up if a run was missed, 30-minute limit. | - (re-registered each run, which is safe) |
| 6 | Install time | Records `InstalledOn` - the start of the grace period. | Already recorded (first install is kept). |
| 7 | First check | Runs the checker once now, so the lock flag exists straight away for the compliance policy. | - |

### What the daily checker does

| Step | Action | What happens |
|---|---|---|
| 1 | Measure | Reads sessions (`quser`) and profile last-use times; works out last activity and idle days. |
| 2 | Idle 14+ days | Logs off every session (`logoff.exe <session id>`) - **unsaved work in those sessions is lost**. Sets `Locked = 1` and `LockedOn`, writes event **2001** (Warning) to the Application log, source `IntuneIdleDeviceLock`. |
| 3 | In use again | With `$KeepLockUntilCleared = $true` (default): stays locked until IT clears it. With `$false`: clears `Locked` and writes event **2002**. |
| 4 | Record | Writes `IdleDays`, `LastActivity` and `LastCheck` to `HKLM\SOFTWARE\IntuneIdleDeviceLock`. |

The device is never restarted.

## Settings in the script

At the top of `Install-IdleDeviceLock.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$IdleDaysThreshold` | `14` | Consecutive idle days before the device is locked. |
| `$LogOffUsers` | `$true` | Log off all user sessions when locking. `$false` = only flag the device non-compliant. |
| `$KeepLockUntilCleared` | `$true` | `$true` = locked devices stay non-compliant until IT clears them. `$false` = the lock clears by itself at the next daily check after someone uses the device. |
| `$CheckTime` | `'09:00'` | Time of the daily check (device local time). The task also runs at every startup. |
| `$ExcludeList` | `@()` | Computer names to skip (wildcards allowed). The lock is **removed** from these devices. |

Example - 30 days, clear automatically when used again, skip lab devices:

```powershell
$IdleDaysThreshold = 30
$KeepLockUntilCleared = $false
$ExcludeList = @('LAB-*', 'KIOSK-*')
```

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | Enough - it installs the scheduled task, which then checks every day by itself. |
| **Re-runs after you change the script** | Changing a setting and uploading again updates the checker and task on every device. The install time (grace period) and an existing lock are kept. |
| **Re-runs for every new user** who signs in (device assignment) | Safe - re-registers the same task. |
| **Retries 3 times** after a failure | Only an install failure counts; the retry installs again. |
| **30-minute time limit** | The install takes seconds; the first check is limited to 5 minutes. |
| **Runs before Win32 apps** | No effect. |

## Prerequisites

- **Windows 10 or Windows 11 Pro, Enterprise or Education.** Custom compliance doesn't support Windows Home, and `quser` / `logoff` aren't available there.
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- An Intune **compliance policy with custom compliance** (below) - without it the device is logged off but not marked non-compliant.
- To block non-compliant devices: a **Conditional Access** policy that requires a compliant device (Microsoft Entra ID P1).
- An Intune role that can add platform scripts and compliance policies, such as **Intune Administrator**.

## Step-by-step: add the platform script in Intune

1. Edit the settings at the top of `Install-IdleDeviceLock.ps1` if needed.
2. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
3. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
4. **Basics**
   - **Name**: `Windows LIPP Lock`
   - **Description**: `Logs off all users and flags the device non-compliant after 14 consecutive idle days.`
   - Select **Next**.
5. **Script settings**
   - **Script location**: browse to `Install-IdleDeviceLock.ps1`.
   - **Run this script using the logged on credentials**: **No**. The script must run as **SYSTEM**: it installs a SYSTEM scheduled task, writes HKLM and protects the install folder.
   - **Enforce script signature check**: **No** (unless you sign the script).
   - **Run script in 64-bit PowerShell host**: **Yes**. (The script also relaunches itself in 64-bit if left at No.)
   - Select **Next**.
6. **Scope tags**: choose scope tags if you use them, then select **Next**.
7. **Assignments**
   - Under **Included groups**, select a **device group**, for example all Windows 10/11 corporate devices. The lock is about the device, so assign to devices, not users. Start with a small **pilot group**.
   - Select **Next**.
8. **Review + add**: check the settings and select **Add**.

## Step-by-step: make locked devices non-compliant (custom compliance)

### 1. Add the discovery script

1. Save this as `Get-IdleDeviceLockState.ps1`:
   ```powershell
   $state = Get-ItemProperty -Path 'HKLM:\SOFTWARE\IntuneIdleDeviceLock' -ErrorAction SilentlyContinue
   $hash = @{
       IdleLockInstalled = [bool]($state -and $state.InstalledOn)
       IdleDeviceLocked  = [bool]($state -and $state.Locked -eq 1)
       IdleDays          = if ($state -and $null -ne $state.IdleDays) { [int]$state.IdleDays } else { 0 }
   }
   return $hash | ConvertTo-Json -Compress
   ```
2. In the Intune admin center go to **Endpoint security > Device compliance > Scripts > Add > Windows 10 and later**.
3. **Name**: `Idle Device Lock state`. **Detection script**: paste the script above.
4. **Run this script using the logged on credentials**: **No**. **Enforce script signature check**: **No**. **Run script in 64 bit PowerShell Host**: **Yes**.
5. Select **Next**, then **Create**.

### 2. Create the JSON rules file

Save this as `IdleDeviceLock.json` (change `MoreInfoUrl` to your own help page):

```json
{
  "Rules": [
    {
      "SettingName": "IdleDeviceLocked",
      "Operator": "IsEquals",
      "DataType": "Boolean",
      "Operand": false,
      "MoreInfoUrl": "https://contoso.com/it/idle-device",
      "RemediationStrings": [
        {
          "Language": "en_US",
          "Title": "This device was locked after a long period without use.",
          "Description": "The device was not used for 14 days in a row, so it was signed out and blocked from company resources. Contact the IT service desk to have it checked and unlocked."
        }
      ]
    }
  ]
}
```

Optional: to also mark devices non-compliant when the lock **isn't installed**, add a second rule with `"SettingName": "IdleLockInstalled"`, `"Operator": "IsEquals"`, `"DataType": "Boolean"`, `"Operand": true`.

### 3. Create the compliance policy

1. Go to **Devices > Compliance > Policies > Create policy**, platform **Windows 10 and later**, then **Create**.
2. **Basics**: Name `Windows LIPP Lock compliance`.
3. **Compliance settings > Custom Compliance**: **Custom compliance** = **Require**. **Select your discovery script**: `Idle Device Lock state`. **Upload and validate the JSON file**: `IdleDeviceLock.json`.
4. **Actions for noncompliance**: keep **Mark device noncompliant** at **0 days** (immediately). Optionally add **Send email to end user**.
5. **Assignments**: the **same device group** as the platform script.
6. **Review + create**.

Then, in Microsoft Entra ID, make sure a **Conditional Access** policy requires a **compliant device** for your company apps - that is what actually blocks a locked device.

## Step-by-step: check the results

1. **Platform script**: **Devices > Scripts and remediations > Platform scripts > Windows LIPP Lock > Device status**. **Success** = installed. The summary line (result message) is available through Microsoft Graph (beta): `deviceManagement/deviceManagementScripts/{id}/deviceRunStates`, property `resultMessage`.
2. **Compliance**: **Devices > Compliance > Policies > Windows LIPP Lock compliance > Device status**. Locked devices are **Not compliant**; open one to see `IdleDeviceLocked = True`. It can take up to 8 hours after a change for compliance to update.
3. **On a device**:
   ```powershell
   Get-ScheduledTask -TaskName 'Intune Idle Device Lock' | Get-ScheduledTaskInfo
   Get-ItemProperty HKLM:\SOFTWARE\IntuneIdleDeviceLock | Select-Object Locked, LockedOn, IdleDays, LastActivity, LastCheck, InstalledOn
   Get-Content C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLock.log -Tail 20
   Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'IntuneIdleDeviceLock' } -MaxEvents 5
   ```

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment or a setting), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device, which updates the checker and task.
- **For specific devices:** remove them from the assigned group, wait for the next check-in, then add them back.
- **New users:** a device-assigned script runs again when a new user signs in; that is safe.
- **Run the daily check now** on a device: `Start-ScheduledTask -TaskName 'Intune Idle Device Lock'`.

## Undo

**Unlock one device** (after IT has reviewed it) - as an administrator on the device:

```powershell
Set-ItemProperty -Path HKLM:\SOFTWARE\IntuneIdleDeviceLock -Name Locked -Value 0
Set-ItemProperty -Path HKLM:\SOFTWARE\IntuneIdleDeviceLock -Name InstalledOn -Value (Get-Date).ToString('s')
```

Resetting `InstalledOn` gives the device a fresh 14-day grace period. Then sync the device (**Settings > Accounts > Access work or school > Info > Sync**, or **Sync** on the device in Intune) so compliance updates. You can also run this remotely with a one-off Intune remediation or platform script.

**Remove the lock completely** from all devices: add their names to `$ExcludeList` (or `'*'` for all) and upload the script again - it removes the task, the checker and the lock flag. Or on one device:

```powershell
Unregister-ScheduledTask -TaskName 'Intune Idle Device Lock' -Confirm:$false
Remove-Item -Recurse -Force C:\ProgramData\IntuneIdleDeviceLock, HKLM:\SOFTWARE\IntuneIdleDeviceLock
```

Remove the platform script's assignment and the compliance policy too, or they will run again.

## Troubleshooting

- **Install log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLockPlatformScript.log`.
- **Daily check log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLock.log` - every check with sessions, last activity, idle days, logoffs and lock changes.
- **Event log**: Application log, source `IntuneIdleDeviceLock` - event **2001** (locked), **2002** (lock cleared).
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`: `IntuneManagementExtension.log` (when the script ran and its result) and `AgentExecutor.log` (exit code and error output).

| Problem | Cause and fix |
|---|---|
| Device locked although it was used | The user was signed in to a session that `quser` doesn't see (for example only through remote tools), or used the device without signing in. Check `LastActivity` in the registry and the daily log. Raise `$IdleDaysThreshold` if needed, and unlock the device (see *Undo*). |
| Device locked straight after a holiday | Expected: days switched off count as idle. Unlock it after checking, or set `$KeepLockUntilCleared = $false` so it clears itself once used. |
| Locked device still compliant | The compliance policy isn't assigned, the discovery script isn't selected, or compliance hasn't run yet (up to 8 hours - sync the device to speed it up). Check the device's compliance details for `IdleDeviceLocked`. Errors 65007-65010 there mean the discovery script failed or returned bad JSON. |
| Non-compliant device can still reach company apps | No Conditional Access policy requires a compliant device, or the app isn't in its scope. |
| Task doesn't run | Check `Get-ScheduledTaskInfo` (`LastTaskResult`). The task needs PowerShell at `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`. |
| Users lost unsaved work | Logging off ends their apps. That only happens after 14 idle days; set `$LogOffUsers = $false` to only flag the device. |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec), then run the check with a short threshold to see a lock:

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-IdleDeviceLock.ps1
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\ProgramData\IntuneIdleDeviceLock\Invoke-IdleDeviceCheck.ps1 -IdleDaysThreshold 0 -LogOffUsers 0
```

The second command locks the device without logging anyone off (threshold 0). Unlock it afterwards (see *Undo*).

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | Lock installed (or removed from an excluded device). Locking itself happens later, in the daily check. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | Install failed (folder, checker, task or registry). See the install log. | Reports **Failed** and runs it again at the next three check-ins. |
