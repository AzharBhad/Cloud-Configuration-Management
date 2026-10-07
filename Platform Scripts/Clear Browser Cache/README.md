# Clear Browser Cache

An Intune **platform script** that makes Microsoft Edge, Google Chrome and Mozilla Firefox **clear their cache every time they close**, and clears the browser caches and temporary web files already on Windows 10 and Windows 11 devices.

Why use it:

- **Removes the browser cache automatically when the browser closes.** The script turns on each browser's own "clear cache on exit" enterprise policy. From then on, the browser deletes its cached images and files every time it closes - no script has to run again.
- **Eliminates temporary web files.** Clears the existing Edge, Chrome and Firefox caches and the Windows temporary internet files (`INetCache`) for every user on the device.
- **Prevents retention of sensitive browsing artifacts.** Cached pages, images, documents and scripts from internal or sensitive sites don't stay on disk, where they could be recovered from a lost, shared or reassigned device.

History, cookies, saved passwords, bookmarks and form data are **not** touched by default, so users stay signed in to websites.

## Files

| File | Purpose |
|---|---|
| `Clear-BrowserCache.ps1` | The platform script you upload to Intune. |
| `README.md` | This document. |

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **Shared or hot-desk devices** | The next user can't find cached content from the previous user's browsing. |
| **Devices handling sensitive data** (finance, HR, healthcare) | Cached copies of sensitive pages and downloads don't build up on disk. |
| **New device setup** | Sets the clear-on-close policies from day one. |
| **One-time clean-up** for a group of devices | Clears large or stale browser caches and temporary web files now, and stops them building up again. |
| **Before reassigning a device** | Removes leftover cached web content (together with a full profile clean-up). |

### How "clear on close" works

A script can't watch for a browser closing. Instead, the script sets the browser's own enterprise policy, which the browser then follows every time it closes:

| Browser | Policy set by the script (machine-wide, `HKLM\SOFTWARE\Policies`) | Effect |
|---|---|---|
| **Microsoft Edge** | `Microsoft\Edge\ClearCachedImagesAndFilesOnExit` = `1` | Cached images and files are deleted each time Edge closes. |
| **Microsoft Edge** (optional) | `Microsoft\Edge\ClearBrowsingDataOnExit` = `1` - only if `$ClearAllBrowsingDataOnExit` is `$true` | **All** browsing data - history, cookies, passwords, form data and cache - is deleted each time Edge closes. Users are signed out of every website. |
| **Google Chrome** | `Google\Chrome\ClearBrowsingDataOnExitList` contains `cached_images_and_files` | Cached images and files are deleted when Chrome closes. **Chrome only applies this policy when Chrome Sync is turned off** - see `$ChromeDisableSync`. |
| **Google Chrome** (optional) | `Google\Chrome\SyncDisabled` = `1` - only if `$ChromeDisableSync` is `$true` | Turns off Chrome Sync so the list above takes effect. |
| **Mozilla Firefox** | `Mozilla\Firefox\SanitizeOnShutdown\Cache` = `1` | The cache is cleared when Firefox closes. |

The policies apply the next time each browser starts. Users see "Your browser is managed by your organization", and can't turn the setting off.

> These are the same policies you can set in the Intune **Settings catalog** (search for *Clear cached images and files when Microsoft Edge closes*, or the Chrome / Firefox policy names). If you already manage browsers with the Settings catalog, you can set the policies there instead and use this script only for the one-time clean-up (`$Browsers` with the policies already set is safe - existing values are left alone).

### What the script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit, so the policies go to the registry the browsers read. | Already 64-bit. |
| 2 | Set policies | Writes the policies in the table above for each browser in `$Browsers`. | A value that is already set correctly is left alone. |
| 3a | Find users | Lists every real user profile on the device (`Win32_UserProfile`, without system profiles). | `$ClearExistingCache` is `$false`; profiles matching `$ExcludeList`. |
| 3b | Clear caches | Empties, for each user: Edge and Chrome `Cache`, `Code Cache` and `GPUCache` folders (every browser profile), Firefox `cache2` folders (every Firefox profile), and `AppData\Local\Microsoft\Windows\INetCache`. | **A browser that user has open** - deleting under a running browser can damage its profile; it is cleared at the next close by the policy anyway. Files in use are skipped silently. |
| 4 | Summary | Writes one line: policies changed, files and MB cleared, files in use, open browsers skipped. | - |

Junctions and symbolic links are never followed, so nothing outside the cache folders can be deleted. The cache folders themselves are kept; only their contents are removed.

## Settings in the script

At the top of `Clear-BrowserCache.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$Browsers` | `@('Edge', 'Chrome', 'Firefox')` | Browsers to configure and clean. Remove any you don't use or manage elsewhere. |
| `$ClearExistingCache` | `$true` | Also clear the caches already on the device now. `$false` = only set the policies. |
| `$ClearAllBrowsingDataOnExit` | `$false` | Edge: delete **all** browsing data (history, cookies, passwords, form data, cache) on close. Users are signed out of websites every time. |
| `$ChromeDisableSync` | `$false` | Chrome: also turn off Chrome Sync, which Chrome needs before it applies the clear-on-exit list. Users can then no longer sync bookmarks and passwords with their Google account. |
| `$ExcludeList` | `@()` | User profile folder names to skip during the clean-up, wildcards allowed. |

Example - Edge and Chrome only, full data clearing in Edge for shared devices, Chrome Sync off, skip a service account:

```powershell
$Browsers = @('Edge', 'Chrome')
$ClearAllBrowsingDataOnExit = $true
$ChromeDisableSync = $true
$ExcludeList = @('svc_*')
```

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | Sets the policies once - that is enough, because the browsers then clear their cache on every close by themselves. The existing caches are cleared once. |
| **Re-runs after you change the script** | Safe: policies already set are left alone, and the caches are cleared again. |
| **Re-runs for every new user** who signs in (device assignment) | Safe: the clean-up runs again for all profiles. |
| **Retries 3 times** after a failure | Only a policy write failure counts as a failure; the retry writes it again. |
| **30-minute time limit** | Usually seconds. Very large caches across many profiles can take a few minutes. |
| **Runs before Win32 apps** | Browsers installed later by Intune still get the policies - they are machine-wide and read when the browser starts. |

If someone deletes the policies later, this script won't notice. To keep them enforced, set them in the Intune **Settings catalog** (see above) - Intune then re-applies them.

## Prerequisites

- **Windows 10 or Windows 11** (Pro, Enterprise or Education).
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- **Microsoft Edge 83** or later for `ClearCachedImagesAndFilesOnExit` (any current Edge).
- For Chrome: Chrome Sync turned off (`$ChromeDisableSync = $true`, or your own Chrome policy), otherwise Chrome ignores the clear-on-exit list. Check the current behavior in Google's Chrome Enterprise policy list for `ClearBrowsingDataOnExitList`.
- No other policy that sets these values differently - for example a Settings catalog or Group Policy setting that turns `ClearCachedImagesAndFilesOnExit` off. The last one written wins.
- An Intune role that can add platform scripts, such as **Intune Administrator** or **Policy and Profile Manager**.

## Step-by-step: add the script in Intune

1. Edit the settings at the top of `Clear-BrowserCache.ps1` if needed.
2. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
3. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
4. **Basics**
   - **Name**: `Clear Browser Cache`
   - **Description**: `Makes Edge, Chrome and Firefox clear their cache when they close, and clears existing browser caches and temporary web files.`
   - Select **Next**.
5. **Script settings**
   - **Script location**: browse to `Clear-BrowserCache.ps1`.
   - **Run this script using the logged on credentials**: **No**. The script must run as **SYSTEM**: the policies are machine-wide (HKLM) and the clean-up covers every user's profile, which needs admin rights.
   - **Enforce script signature check**: **No** (unless you sign the script).
   - **Run script in 64-bit PowerShell host**: **Yes**. (The script also relaunches itself in 64-bit if left at No.)
   - Select **Next**.
6. **Scope tags**: choose scope tags if you use them, then select **Next**.
7. **Assignments**
   - Under **Included groups**, select a **device group**, for example shared devices or all Windows 10/11 corporate devices. The policies apply to the whole device, so assign to devices, not users. Start with a small **pilot group**.
   - Select **Next**.
8. **Review + add**: check the settings and select **Add**.

## Step-by-step: check the results

1. Go to **Devices > Scripts and remediations > Platform scripts** and open **Clear Browser Cache**.
2. Open **Device status**:
   - **Success** - policies in place and the clean-up finished.
   - **Failed** - a policy couldn't be written; Intune retries 3 times. See the log.
3. The summary line is stored as the script's result message, available through Microsoft Graph (beta): `deviceManagement/deviceManagementScripts/{id}/deviceRunStates`, property `resultMessage`.
4. Check a device:
   - **Edge**: open `edge://policy` - `ClearCachedImagesAndFilesOnExit` shows **true**, status **OK**. `edge://settings/clearBrowsingDataOnClose` shows **Cached images and files** turned on and locked.
   - **Chrome**: open `chrome://policy` - `ClearBrowsingDataOnExitList` lists `cached_images_and_files` with status **OK** (a warning there usually means sync is still on).
   - **Firefox**: open `about:policies` - `SanitizeOnShutdown` shows `Cache: true`.
   - Registry:
     ```powershell
     Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Edge | Select-Object ClearCachedImagesAndFilesOnExit, ClearBrowsingDataOnExit
     Get-ItemProperty HKLM:\SOFTWARE\Policies\Google\Chrome\ClearBrowsingDataOnExitList
     Get-ItemProperty HKLM:\SOFTWARE\Policies\Mozilla\Firefox\SanitizeOnShutdown
     ```
5. Test: browse to a few sites, close the browser completely, and check the `Cache` folder (for example `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache`) is emptied.

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment or a setting), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device.
- **For specific devices:** remove them from the assigned group, wait for the next check-in, then add them back. Or assign the script to a new group containing just those devices.
- **New users:** a device-assigned script runs again when a new user signs in, which clears the caches again.

## Undo

The cleared cache files can't be restored - browsers rebuild their caches as users browse, so nothing is lost. To stop the browsers clearing their cache on close, remove the policies (run as administrator):

```powershell
Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Edge -Name ClearCachedImagesAndFilesOnExit, ClearBrowsingDataOnExit -ErrorAction SilentlyContinue
Remove-Item -Path HKLM:\SOFTWARE\Policies\Google\Chrome\ClearBrowsingDataOnExitList -Recurse -ErrorAction SilentlyContinue
Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Google\Chrome -Name SyncDisabled -ErrorAction SilentlyContinue
Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Mozilla\Firefox\SanitizeOnShutdown -Name Cache -ErrorAction SilentlyContinue
```

Only remove `SyncDisabled` if this script set it (`$ChromeDisableSync = $true`) and no other policy needs it. Remove the script's assignment first, or it may run again. The change applies when each browser restarts.

## Troubleshooting

- **Script log on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ClearBrowserCachePlatformScript.log` lists each policy (set / already set / failed), each cache folder cleared with file count and size, and each open browser skipped.
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`:
  - `IntuneManagementExtension.log` - when the script was received and run, and its result.
  - `AgentExecutor.log` - the PowerShell run itself, including exit code and any error output.

| Problem | Cause and fix |
|---|---|
| Edge doesn't clear its cache on close | Check `edge://policy`. If the policy isn't listed, the script ran in 32-bit without relaunching, or another policy removed it. If it shows an error, a Settings catalog or Group Policy setting conflicts - remove one of them. Background Edge processes (Startup boost, "Continue running background extensions") can keep Edge "open"; the cache is cleared when Edge fully closes. |
| Chrome ignores the policy | Chrome Sync is still on. Set `$ChromeDisableSync = $true` and run again, or turn sync off with your own Chrome policy. `chrome://policy` shows a warning on the policy until then. |
| `Skipped ... the browser is open` in the log | Expected - that user had the browser open. The policy clears that cache when they close it. |
| Many files `in use` | Expected for a signed-in user's open apps that use web content (for example Teams or Outlook web views using INetCache). They are cleared at a later run or by the browser policy. |
| Users complain they are signed out of websites | `$ClearAllBrowsingDataOnExit` is `$true` (Edge deletes cookies on close). Set it to `$false` and remove `ClearBrowsingDataOnExit` (see *Undo*). |
| Script shows **Failed** | A policy couldn't be written. Check the log for the policy name and error, and `AgentExecutor.log`. |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec):

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Clear-BrowserCache.ps1
```

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | Policies set (or already set) and the cache clean-up finished. Files in use and open browsers skipped are not failures. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | A policy couldn't be written, or the script failed. See the log. | Reports **Failed** and runs it again at the next three check-ins. |
