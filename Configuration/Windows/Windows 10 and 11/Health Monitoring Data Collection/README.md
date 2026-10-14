# Health and Monitoring Data Collection

Turns on **Windows health monitoring** with the **Endpoint analytics** scope on Windows 10 and 11, so Intune can collect startup performance, app reliability and other user-experience data. Delivered as an Intune **Templates > Windows health monitoring** profile.

## Purpose

**Endpoint analytics** measures the end-user experience, such as startup and sign-in times, app reliability and Work From Anywhere readiness. It gives scores and recommendations, and **Advanced Analytics** builds on it.

Devices only send that data when a **Windows health monitoring** profile enables it. This policy is equivalent to the *Intune data collection policy* that Endpoint analytics creates during onboarding. Keep **one** of them (see the conflict guidance).

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Health and Monitoring Data Collection` (as shown in the screenshot) |
| Description | Enables Windows health monitoring with the Endpoint analytics scope. |
| Platform | Windows 10 and later |
| Profile type | Templates > **Windows health monitoring** |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations` |
| `@odata.type` | `#microsoft.graph.windowsHealthMonitoringConfiguration` |
| File | `Health-Monitoring-Data-Collection.json` (complete Graph request body) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all Intune-managed and co-managed Windows devices. |
| Supported OS | Windows 10 1903 or later / Windows 11 (Pro, Enterprise, Education); see the Endpoint analytics prerequisites |

> [!NOTE]
> The JSON is the **complete Graph request body** for the *Windows health monitoring* template (`windowsHealthMonitoringConfiguration`); `allowDeviceHealthMonitoring` and `configDeviceHealthMonitoringScope` are verified properties. The admin center scope **Endpoint analytics** is set here as `bootPerformance` (*Boot performance events*). Confirm against a policy exported from your tenant with `GET /beta/deviceManagement/deviceConfigurations/{id}`, and replace `<windows-admin-scope-tag-id>`.

## Configuration settings

### Windows health monitoring

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Health monitoring | **Enable** | `allowDeviceHealthMonitoring` = `enabled` (CSP `DeviceHealthMonitoring/AllowDeviceHealthMonitoring`) | Turns on event collection for analytics. |
| Scope | **Endpoint analytics** | `configDeviceHealthMonitoringScope` = `bootPerformance` (CSP `DeviceHealthMonitoring/ConfigDeviceHealthMonitoringScope`) | Collects the events Endpoint analytics needs. |

**Also check (tenant settings, not in this profile):**
- **Tenant administration > Connectors and tokens > Windows data** = **On**, which is needed for Windows Update reports.
- Windows diagnostic data is at least **Required** level.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 (Endpoint analytics). Advanced Analytics needs the Intune Suite or an Advanced Analytics add-on. |
| Windows | Windows 10 1903 or later / Windows 11, Microsoft Entra joined or hybrid joined |
| Co-management | **Device Configuration** workload in Intune |
| Network | Access to the Endpoint analytics and diagnostic data endpoints |
| Role | **Policy and Profile Manager** or Intune Administrator |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Templates > Windows health monitoring**, then select **Create**. (If it isn't listed, use **Reports > Endpoint analytics > Settings > Intune data collection policy**.)
3. **Basics**:
   - **Name**: `Windows - Health and Monitoring Data Collection`
   - **Description**: Enables Windows health monitoring with the Endpoint analytics scope.
   - Select **Next**.
4. **Configuration settings**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Health monitoring | Enable |
   | 2 | Scope | Endpoint analytics |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add all managed Windows **device** groups. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Replace <windows-admin-scope-tag-id> in the JSON
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value | Select-Object id, displayName

# 2. Create the template profile
$body = Get-Content ".\Health-Monitoring-Data-Collection.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -Body $body -ContentType "application/json"

# 3. Assign to a device group
$assign = @{ assignments = @(@{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<windows-device-group-id>" } }) } | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)/assign" -Body $assign -ContentType "application/json"

# Export an existing profile to compare
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)" | ConvertTo-Json -Depth 10
```

## Assignment & conflict guidance

- **Only one health monitoring profile per device.** The **Intune data collection policy** that Endpoint analytics creates is also a Windows health monitoring profile. Either use it **or** this policy, not both on the same devices, or the Scope setting can conflict.
- **Assign to device groups.**

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Reports > Endpoint analytics**. Scores and device data appear once enough devices report, typically within 24–48 hours.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check `HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceHealthMonitoring` for `AllowDeviceHealthMonitoring = 1` and a scope value.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | The Intune data collection policy and this policy both assigned | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| No data in Endpoint analytics | Fewer than the minimum devices reporting, diagnostic data blocked, or Device Configuration workload in ConfigMgr | Wait 24–48 hours. Check diagnostic data and the co-management workload. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Startup performance data is collected from the **next restarts**.

## Rollback

- **Unassign or delete** the profile. Data collection stops (reverts). Data already collected stays in Endpoint analytics according to its retention.

## References

- [Use Windows Health Monitoring profile](https://learn.microsoft.com/intune/device-configuration/templates/configure-health-monitoring-windows)
- [Configure endpoint analytics](https://learn.microsoft.com/intune/endpoint-analytics/configure)
- [windowsHealthMonitoringConfiguration resource type](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windowshealthmonitoringconfiguration?view=graph-rest-beta)
- [windowsHealthMonitoringScope enum](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windowshealthmonitoringscope?view=graph-rest-beta)
