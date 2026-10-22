# Windows Inactivity Timeout 10 Minutes

Locks Windows 10 and 11 devices after **10 minutes (600 seconds)** without keyboard or mouse input. Delivered as an Intune **settings catalog** policy.

## Purpose

An unlocked, unattended device lets anyone who walks past use the signed-in user's session: email, files, Teams, admin consoles and saved browser sessions. Locking the session automatically after a short idle time closes that gap without relying on users pressing **Windows + L**.

- **Security**: limits the window for opportunistic access to an unattended device.
- **Compliance**: CIS and the Azure Windows security baseline expect *Interactive logon: Machine inactivity limit* to be **900 seconds or fewer, but not 0**. 600 seconds meets that.
- **User experience**: users have to sign in again (PIN, Windows Hello or password) after 10 minutes of inactivity. Video playback and presentations normally keep the device active; see Troubleshooting for idle-timer issues.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows Inactivity Timeout 10 Minutes` (as requested) |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm` |
| File | `Inactivity-Timeout.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin (`<windows-admin-scope-tag-id>`, same as the other Windows policies in this repo) |
| Recommended assignment | **Device** groups: corporate Windows devices. Pilot group first. |
| Supported OS | Windows 10 version 1709 or later, Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSP, its range and its meaning (below), but doesn't publish the settings catalog **definition ID** for it. So the JSON holds only the verified policy metadata and an empty `settings` array. Add the setting in the admin center (steps below), then export the policy with Graph and **replace this JSON with the export**.

## Configuration settings

### Local Policies Security Options

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Interactive Logon Machine Inactivity Limit | **600** | `./Device/Vendor/MSFT/Policy/Config/LocalPoliciesSecurityOptions/InteractiveLogon_MachineInactivityLimit` (integer, seconds, range 0-599940, default 0 = not enforced). Catalog definition ID: take it from the export. | After 600 seconds without input, Windows starts the screen saver and **locks the session**. Device scope: applies to every user who signs in. Same as the GPO *Interactive logon: Machine inactivity limit* (registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\InactivityTimeoutSecs`). |

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, version 1709 or later. Not Home. |
| Enrollment | Intune-enrolled Windows devices (Microsoft Entra joined or hybrid joined) |
| Role | Intune Administrator or Policy and Profile Manager |
| Dependencies | None |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center**.
2. Go to **Devices > Manage devices > Configuration > Create > New policy**.
3. **Platform**: **Windows 10 and later**. **Profile type**: **Settings catalog**. Select **Create**.
4. **Basics**:
   - **Name**: `Windows Inactivity Timeout 10 Minutes`
   - **Description**: `Locks the Windows session after 10 minutes (600 seconds) without keyboard or mouse input.`
5. **Configuration settings** > **Add settings**:
   - Search for **Interactive Logon Machine Inactivity Limit**.
   - Select the category **Local Policies Security Options** and tick **Interactive Logon Machine Inactivity Limit**.
   - Close the settings picker and enter **600**.
6. **Scope tags**: **Windows Admin**.
7. **Assignments**: **Included groups** > a **device** group of corporate Windows devices (start with a pilot group). Exclude kiosks or meeting-room devices that must never lock, if any.
8. **Review + create** > **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

The JSON creates the policy shell only (no setting). Use it for consistent naming, then add the setting in the admin center, or import the complete export once you have it.

```powershell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# Replace <windows-admin-scope-tag-id> in the JSON first (or use "0" for Default).
$body   = Get-Content -Raw ".\Inactivity-Timeout.json"
$policy = Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
  -Body $body -ContentType "application/json"

# Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<device-group-object-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"
```

**Export the complete policy** (after the setting is added in the admin center) and save it over `Inactivity-Timeout.json`:

```powershell
$id = "<policy-id>"
$p  = Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$id`?`$expand=settings"
$p | Select-Object name, description, platforms, technologies, roleScopeTagIds, settings |
  ConvertTo-Json -Depth 20 | Set-Content ".\Inactivity-Timeout.json" -Encoding UTF8
```

To look up the definition ID directly:

```powershell
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationSettings?`$filter=contains(id,'machineinactivitylimit')&`$select=id,displayName"
```

## Assignment & conflict guidance

- **Device targeting**: the setting is device-scoped (it doesn't apply to user scope), so assign to **device** groups. It then applies to every user on the device.
- **Conflicts in this repo**: none. No other Windows policy in `Configuration/` or `Compliance/` sets this value or another lock timer.
- **Security baselines**: the Intune **Windows security baseline** can also configure *Interactive Logon Machine Inactivity Limit*. If it's assigned to the same devices, set the same value in both or configure it in only one place; different values show as **Conflict**.
- **Other lock timers**: Device Lock *Max Inactivity Time Device Lock*, screen saver timeout (ADMX) and power settings also lock or blank the screen. When several are set, the **shortest** one wins, which confuses users. Use this setting as the single lock timer.
- **Group Policy**: if hybrid joined devices also get the GPO *Interactive logon: Machine inactivity limit*, both write the same registry value. Remove it from the GPO, or make MDM win with *ControlPolicyConflict/MDMWinsOverGP* (which applies to Policy CSP settings).

## Validation

**Admin center**
- The policy > **Device status** and **Per setting status**: devices should show **Succeeded**.
- **Devices > Monitor > Assignment failures** for errors.

**On a device**
1. Force a sync: **Settings > Accounts > Access work or school** > the work account > **Info** > **Sync**. Devices also check in about every 8 hours.
2. Check the value (PowerShell as admin):
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name InactivityTimeoutSecs
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\LocalPoliciesSecurityOptions" -ErrorAction SilentlyContinue
   ```
   `InactivityTimeoutSecs` should be **600**.
3. Leave the device idle for 10 minutes: the session should lock.
4. If it doesn't apply: **Event Viewer > Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin**, or run `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning;Autopilot -cab C:\Temp\mdm.cab`, or **Export your management log files** on the Info page.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | Device hasn't checked in | Sync from Access work or school, or wait for the next check-in (about 8 hours). |
| **Not applicable** | Windows Home, or older than 1709 | Upgrade the edition or version. |
| **Conflict** | Security baseline or another policy sets a different value | Set the same value everywhere or remove it from one policy. |
| **Error** | Wrong value (outside 0-599940) | Enter 600. |
| Value applied but screen doesn't lock | Something keeps the idle timer active: a docking station peripheral sending input, an app holding a display request, presentation mode | Run `powercfg /requests` as admin to find the request; test with peripherals unplugged; turn off presentation settings. |
| Lock after a different time | A shorter timer (Device Lock, screen saver, power settings) is also set | Remove the other timer so only this one applies. |
| Change takes effect only after sign-out | Some devices pick up the new value at next sign-in | Ask users to sign out and in, or restart. |

## Rollback

- Unassign or delete the policy.
- Security Options values set through the Policy CSP **may stay on the device** (tattooed) after the policy is removed. To be sure it's reverted, deploy a policy that sets **Interactive Logon Machine Inactivity Limit = 0** (not enforced) to the same devices, confirm the registry value is `0`, then remove that policy.

## References

- [Policy CSP - LocalPoliciesSecurityOptions: InteractiveLogon_MachineInactivityLimit](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-localpoliciessecurityoptions#interactivelogon_machineinactivitylimit)
- [Use the settings catalog to configure settings on Windows devices](https://learn.microsoft.com/intune/intune-service/configuration/settings-catalog)
- [Windows security baseline (Azure guest configuration): Interactive logon: Machine inactivity limit](https://learn.microsoft.com/azure/governance/policy/samples/guest-configuration-baseline-windows#security-options---interactive-logon)
- [deviceManagementConfigurationPolicy resource type (Graph beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta)
- [Policy CSP - ControlPolicyConflict (MDMWinsOverGP)](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-controlpolicyconflict)
