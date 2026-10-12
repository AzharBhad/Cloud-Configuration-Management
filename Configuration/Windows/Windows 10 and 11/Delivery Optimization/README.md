# Windows - Delivery Optimization

Configures Windows Delivery Optimization (peer-to-peer content sharing for Windows updates, Microsoft Store and Intune Win32 apps) on **Windows 10 and 11** devices.

## Purpose

Delivery Optimization lets Windows devices download content from each other instead of all of them going to the internet. This policy:

- **Cuts WAN and internet bandwidth.** Devices in the same group share Windows updates, feature updates, Microsoft 365 Apps, Store apps and Win32 apps.
- **Keeps peering on the local network.** Peering is limited to devices in the same Group ID (from DHCP) and the same subnet, so content doesn't cross slow links between sites.
- **Protects user experience.** Foreground downloads can use up to 75% of the available bandwidth, background downloads up to 50%.
- **Protects small or low-power devices.** Devices only peer when they have at least 4 GB RAM, 40 GB disk and 30% battery.
- **Speeds up patching**, which helps devices meet the compliance policies in [`Compliance/Windows`](../../../../Compliance/Windows) that need current Defender signatures and OS updates.

## Policy summary

| Item | Value |
|---|---|
| Name | `Windows - Delivery Optimization` (from the screenshot; the top of the title is partly cut off) |
| Platform | Windows 10 and later |
| Profile type | **Templates > Delivery Optimization** |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations` |
| `@odata.type` | `#microsoft.graph.windowsDeliveryOptimizationConfiguration` |
| File | `Delivery-Optimization.json` |
| Scope tags | **Windows Admin** |
| Recommended assignment | Device groups (all settings are device-scoped), for example all corporate Windows devices. Exclude Windows 365 Cloud PCs; see the guidance on assignments and conflicts below. |
| Supported OS | Windows 10 1803 or later, and Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!IMPORTANT]
> In **April 2025** Microsoft deprecated the original Delivery Optimization template. The screenshot shows a profile made with that original template. Existing profiles keep working and can be edited, but **you can't create new profiles of the old type**. **Templates > Delivery Optimization** now opens a new template that uses the **settings catalog format**.
>
> - **To recreate this policy**, use the admin center steps below. They configure the same Policy CSP settings with the same values in the new template.
> - **The JSON** is the Graph representation of the profile in the screenshot (`windowsDeliveryOptimizationConfiguration`). Use it to document, back up, compare against or `PATCH` the existing profile. A `POST` of this type may be rejected now that the template is deprecated. In that case, build the policy in the new template and export it (see the Graph PowerShell section).

## Configuration settings

### Delivery Optimization

| Setting (admin center name) | Value | Graph property | Policy CSP | What it does / why |
|---|---|---|---|---|
| Download mode | HTTP blended with peering across private group (2) | `deliveryOptimizationMode` = `httpWithPeeringPrivateGroup` | `DODownloadMode` = 2 | Peers with devices that have the same Group ID, across NAT boundaries. Microsoft recommends this mode for most organisations. |
| Restrict Peer Selection | Subnet mask | `restrictPeerSelectionBy` = `subnetMask` | `DORestrictPeerSelectionBy` = 1 | Only peers with devices on the same subnet, which stops traffic crossing slow links between sites. Windows 10 1803 or later. |
| Group ID source | DHCP user option | `groupIdSource` → `deliveryOptimizationGroupIdSourceOptions.groupIdSourceOption` = `dhcpUserOption` | `DOGroupIdSource` = 3 | The client reads **DHCP Option ID 234** and uses the GUID it returns as its Group ID. If the option is missing, it falls back to AD site, then domain SID, then Entra tenant ID. |

### Bandwidth

| Setting | Value | Graph property | Policy CSP | What it does / why |
|---|---|---|---|---|
| Bandwidth optimization type | Percentage | `bandwidthMode` → `#microsoft.graph.deliveryOptimizationBandwidthPercentage` | — | Bandwidth is limited as a percentage of what's available. |
| Maximum foreground download bandwidth (in %) | 75 | `maximumForegroundBandwidthPercentage` = 75 | `DOPercentageMaxForegroundBandwidth` = 75 | Cap for downloads the user starts, such as Company Portal installs. |
| Maximum background download bandwidth (in %) | 50 | `maximumBackgroundBandwidthPercentage` = 50 | `DOPercentageMaxBackgroundBandwidth` = 50 | Cap for background downloads such as Windows Update. Downloads from LAN peers aren't throttled. |
| Delay background HTTP download (in seconds) | 600 | `backgroundDownloadFromHttpDelayInSeconds` = 600 | `DODelayBackgroundDownloadFromHttp` = 600 | Looks for a peer for up to 10 minutes before falling back to HTTP. Microsoft recommends 60 seconds. 600 favours peering, but background downloads may look stalled for up to 10 minutes. |
| Delay foreground HTTP download (in seconds) | 60 | `foregroundDownloadFromHttpDelayInSeconds` = 60 | `DODelayForegroundDownloadFromHttp` = 60 | Looks for a peer for up to 60 seconds before falling back to HTTP. This is Microsoft's recommended value. |

### Caching

| Setting | Value | Graph property | Policy CSP | What it does / why |
|---|---|---|---|---|
| Minimum RAM required for peer caching (in GB) | 4 | `minimumRamAllowedToPeerInGigabytes` = 4 | `DOMinRAMAllowedToPeer` = 4 | Only devices with at least 4 GB RAM peer. This is Microsoft's recommended value. |
| Minimum disk size required for peer caching (in GB) | 40 | `minimumDiskSizeAllowedToPeerInGigabytes` = 40 | `DOMinDiskSizeAllowedToPeer` = 40 | Only devices with a disk of at least 40 GB peer. Microsoft recommends 32 GB here; the Graph documentation suggests 64–256 GB. |
| Minimum content file size for peer caching (in MB) | 10 | `minimumFileSizeToCacheInMegabytes` = 10 | `DOMinFileSizeToCache` = 10 | Only files of 10 MB or more are peered. This is Microsoft's recommended value; the Windows default is 50 MB. |
| Minimum battery level required to upload (in %) | 30 | `minimumBatteryPercentageAllowedToUpload` = 30 | `DOMinBatteryPercentageAllowedToUpload` = 30 | Uploads to peers pause when a device on battery drops below 30%. Microsoft recommends 40%. |
| Maximum cache age (in days) | 30 | `maximumCacheAgeInDays` = 30 | `DOMaxCacheAge` = 2592000 seconds | Cached files are kept for 30 days. Intune converts days to seconds on the device. |
| Maximum cache size type | Absolute | `maximumCacheSize` → `#microsoft.graph.deliveryOptimizationMaxCacheSizeAbsolute` | — | The cache size is a fixed amount in GB. |
| Absolute maximum cache size (in GB) | 6 | `maximumCacheSizeInGigabytes` = 6 | `DOAbsoluteMaxCacheSize` = 6 | The cache can use at most 6 GB. This overrides `DOMaxCacheSize`. A 6 GB cache can't hold a full feature update plus other content for 30 days, so older files are evicted early. Consider 10–20 GB if disks allow. |
| VPN peer caching | Enabled | `vpnPeerCaching` = `enabled` | `DOAllowVPNPeerCaching` = 1 | Lets devices on VPN peer with other domain-network devices. |

### Not configured

These settings appear in the template but weren't set in the screenshot, so they're left out of the JSON: **Modify cache drive**, **Cache server host names**, **Delay foreground download cache server fallback**, **Delay background download cache server fallback**.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, Windows 10 1803 or later / Windows 11 (the CSP isn't supported on Home) |
| Enrollment | Intune-enrolled devices: Entra joined, hybrid Entra joined, or co-managed with the device configuration workload moved to Intune |
| Role | Intune Administrator, or **Policy and Profile Manager** with the **Windows Admin** scope tag |
| Network: DHCP | Configure **DHCP Option 234** on each site's DHCP scope with a per-site GUID (string). Without it, Group ID falls back to AD site, then domain SID, then Entra tenant ID. |
| Network: firewall | Allow TCP **7680** inbound between clients for LAN peering. Allow outbound HTTPS to the Delivery Optimization cloud service (`*.do.dsp.mp.microsoft.com`). |
| Service | The **Delivery Optimization** service (`DoSvc`) must not be disabled |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**.
3. Set **Platform** to **Windows 10 and later** and **Profile type** to **Templates**. Select **Delivery Optimization**, then **Create**.
4. **Basics**:
   - **Name**: `Windows - Delivery Optimization`
   - **Description**: copy it from the JSON
   - Select **Next**.
5. **Configuration settings**. The new template uses settings catalog names, shown in brackets below. Hover the info icon to confirm each setting's CSP.

   | # | Setting | Value |
   |---|---|---|
   | 1 | Download mode (*DO Download Mode*) | HTTP blended with peering across a private group (2) |
   | 2 | Restrict Peer Selection (*DO Restrict Peer Selection By*) | Subnet mask (1) |
   | 3 | Group ID source (*DO Group Id Source*) | DHCP Option ID (3) |
   | 4 | Max foreground download bandwidth % (*DO Percentage Max Foreground Bandwidth*) | 75 |
   | 5 | Max background download bandwidth % (*DO Percentage Max Background Bandwidth*) | 50 |
   | 6 | Delay background HTTP download (*DO Delay Background Download From Http*) | 600 |
   | 7 | Delay foreground HTTP download (*DO Delay Foreground Download From Http*) | 60 |
   | 8 | Minimum RAM for peer caching (*DO Min RAM Allowed To Peer*) | 4 |
   | 9 | Minimum disk size for peer caching (*DO Min Disk Size Allowed To Peer*) | 40 |
   | 10 | Minimum content file size (*DO Min File Size To Cache*) | 10 |
   | 11 | Minimum battery level to upload (*DO Min Battery Percentage Allowed To Upload*) | 30 |
   | 12 | Maximum cache age (*DO Max Cache Age*) | 30 days. In the settings catalog format this value is in **seconds**: **2592000**. |
   | 13 | Absolute max cache size (*DO Absolute Max Cache Size*) | 6 |
   | 14 | VPN peer caching (*DO Allow VPN Peer Caching*) | Allowed / Enabled (1) |

   Select **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add your Windows **device** group. Optionally, exclude Cloud PCs with a filter (see the guidance below). Select **Next**.
8. **Applicability rules** (optional): add **Assign profile if OS edition is** Windows 10/11 Enterprise, Pro and Education, to stop Home editions reporting errors. Select **Next**.
9. **Review + create**: check every value, then select **Create**.

> [!NOTE]
> To edit the **existing** profile from the screenshot, open **Devices > Manage devices > Configuration > Windows - Delivery Optimization > Properties > Configuration settings > Edit**. That profile keeps the original template's display names, such as *Bandwidth optimization type* and *Maximum cache size type*.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the Windows Admin scope tag ID and replace <windows-admin-scope-tag-id> in the JSON
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2a. Update the EXISTING legacy profile with the JSON (recommended for this file)
$existing = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Windows - Delivery Optimization'").value[0]
$body = Get-Content ".\Delivery-Optimization.json" -Raw
Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($existing.id)" -Body $body -ContentType "application/json"

# 2b. Or create it (may be rejected because the legacy template is deprecated)
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -Body $body -ContentType "application/json"

# 3. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<windows-device-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

**New template (settings catalog format).** After you create the policy in the admin center, export it to get the exact setting definition IDs. Then keep that export as the import body for other tenants:

```powershell
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Delivery Optimization'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 20 | Out-File ".\Delivery-Optimization-SettingsCatalog.json"
```

## Assignment & conflict guidance

- **Assign to device groups.** Every Delivery Optimization CSP setting is device-scoped.
- **Only one Delivery Optimization policy per device.** The same CSP settings can also come from:
  - a **settings catalog** policy with *Delivery Optimization* settings;
  - the new **Delivery Optimization** template;
  - **Windows Update rings**, whose legacy *Delivery optimization download mode* setting overlaps `DODownloadMode`;
  - the **Windows security baseline**, if a version sets DO values.

  Two of these on the same device causes a **Conflict**.
- **Windows 365 Cloud PCs.** Peering between Cloud PCs brings little benefit. Exclude them with a filter: `(device.model -contains "Cloud PC") or (device.model -contains "Windows 365")`. This is the same filter the [Windows 365 compliance policy](../../../../Compliance/Windows/Windows%2010%20and%2011/Windows%20365%20Cloud%20PC) uses.
- **GPO.** If a GPO also sets *Windows Components > Delivery Optimization*, the GPO value wins unless **MDMWinsOverGP** (`ControlPolicyConflict/MDMWinsOverGP`) is enabled. Remove the GPO, or enable MDMWinsOverGP, on co-managed or hybrid devices. Use **Group Policy analytics** to compare an existing GPO.
- **Configuration Manager / Connected Cache.** If you add Microsoft Connected Cache later, set *Cache server host names* in this same policy rather than in a new one.

## Validation

**In the admin center**
- Open **Devices > Manage devices > Configuration >** the profile **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Reports > Windows updates > Delivery Optimization** for peer-traffic percentages.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the policy registry values:
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization"
   ```
   Expect `DODownloadMode = 2`, `DORestrictPeerSelectionBy = 1`, `DOGroupIdSource = 3`, `DOMaxCacheAge = 2592000` and `DOAbsoluteMaxCacheSize = 6`.
3. Check the effective configuration and peer activity:
   ```powershell
   Get-DOConfig -Verbose
   Get-DeliveryOptimizationStatus
   Get-DeliveryOptimizationPerfSnap
   ```
   Also check **Settings > Windows Update > Advanced options > Delivery Optimization > Activity monitor**.
4. Check the Group ID from DHCP with `Get-DOConfig`, or check Delivery Optimization logs with `Get-DeliveryOptimizationLog`.
5. For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync from Company Portal or Access work or school. Check the device is online. |
| **Not applicable** | Home edition or Windows older than 1803 | Upgrade the edition or version. Add an applicability rule. |
| **Conflict** | Another profile, update ring or baseline sets a DO setting | Use **Per-setting status** to find the other profile and remove the duplicate setting. |
| **Error** on Group ID source / Restrict peer selection | Windows earlier than 1803 | Update Windows. |
| No peer traffic (0% in reports) | TCP 7680 is blocked, DHCP Option 234 is missing or different per subnet, peering is restricted by subnet, or devices are below the RAM/disk/battery thresholds | Open the firewall port. Check the DHCP option. Check `Get-DOConfig`. Note that peering only starts for files of 10 MB or more. |
| Background downloads look stuck for about 10 minutes | **Delay background HTTP download** is 600 seconds and no peer has the content | Expected behaviour. Lower it to 60 seconds (Microsoft's recommendation) if this causes problems. |
| Content evicted quickly or low peer hit rate | The 6 GB absolute cache is too small for feature updates | Raise **Absolute maximum cache size**. |
| Settings ignored on hybrid devices | A GPO sets the same DO values | Remove the GPO or enable MDMWinsOverGP. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to device groups. |

No restart is needed. `DoSvc` reads the policy the next time it runs a job.

## Rollback

- **Unassign or delete** the profile. Intune removes the Delivery Optimization policy values from `PolicyManager`, and the settings **revert** to Windows defaults (download mode LAN (1), 3-day cache age, 20% cache size). They aren't tattooed.
- To roll back only peering, change **Download mode** to **HTTP only, no peering (0)** instead of deleting the profile. This keeps the bandwidth limits.
- If a value is still there after removal, check for a GPO that sets the same setting (`HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization`).

## References

- [Delivery Optimization settings in Microsoft Intune](https://learn.microsoft.com/intune/intune-service/configuration/delivery-optimization-windows)
- [Delivery Optimization settings for Windows devices in Intune (original template)](https://learn.microsoft.com/intune/intune-service/configuration/delivery-optimization-settings)
- [Delivery Optimization reference](https://learn.microsoft.com/windows/deployment/do/waas-delivery-optimization-reference)
- [Policy CSP – DeliveryOptimization](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-deliveryoptimization)
- [windowsDeliveryOptimizationConfiguration resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windowsdeliveryoptimizationconfiguration?view=graph-rest-beta)
- [Use the settings catalog to configure settings](https://learn.microsoft.com/intune/intune-service/configuration/settings-catalog)
