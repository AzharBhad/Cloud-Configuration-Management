<#
.SYNOPSIS
    Intune platform script.
    Makes Microsoft Edge, Google Chrome and Mozilla Firefox clear their cache every time they close,
    and clears the browser caches and temporary web files that already exist on the device.

.DESCRIPTION
    A script can't watch for a browser closing, so the "clear on close" part is done the supported
    way: the script sets each browser's own enterprise policy, and from then on the browser clears
    its cache itself every time it closes. The script also removes the caches already on the device.

    Actions, in this order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit (so it writes the
         64-bit registry, which is where the browsers read their policies).
      2. Sets the clear-on-close policies (machine-wide, HKLM\SOFTWARE\Policies) for each browser in
         $Browsers. Only values that aren't already set are written:
           Edge    : ClearCachedImagesAndFilesOnExit = 1
                     ClearBrowsingDataOnExit = 1         (only if $ClearAllBrowsingDataOnExit is $true)
           Chrome  : ClearBrowsingDataOnExitList adds "cached_images_and_files"
                     SyncDisabled = 1                    (only if $ChromeDisableSync is $true - Chrome
                                                          applies the list only when sync is off)
           Firefox : SanitizeOnShutdown\Cache = 1
      3. If $ClearExistingCache is $true, for every user profile on the device (except $ExcludeList):
           - Edge and Chrome   : Cache, Code Cache and GPUCache folders of every browser profile
           - Firefox           : cache2 folder of every Firefox profile
           - Temporary web files: AppData\Local\Microsoft\Windows\INetCache
         A browser's cache is skipped for a user while that user has the browser open (the files are
         in use, and deleting them under a running browser can damage its profile). Files in use are
         skipped silently. Junctions and symbolic links are never followed.
      4. Writes a summary line.

    History, cookies, passwords, bookmarks and form data are NOT touched, unless you turn on
    $ClearAllBrowsingDataOnExit (Edge). The script is safe to run more than once. No restart is
    needed; the policies apply the next time each browser starts.

    Exit codes:
      0 = Policies set (or already set) and the cache cleanup finished.
      1 = A policy could not be written, or the script failed. See the log.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No  (runs as SYSTEM - writing machine-wide
                                                             browser policies and cleaning every
                                                             user's profile need admin rights)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Log file: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ClearBrowserCachePlatformScript.log
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# Browsers to configure and clean: any of 'Edge', 'Chrome', 'Firefox'
$Browsers = @('Edge', 'Chrome', 'Firefox')

# Clear the caches that already exist on the device now (in addition to setting the policies)
$ClearExistingCache = $true

# Edge only: clear ALL browsing data on close - history, cookies, passwords, form data and cache.
# Users are signed out of websites every time. Leave $false unless you need this.
$ClearAllBrowsingDataOnExit = $false

# Chrome only applies ClearBrowsingDataOnExitList when Chrome Sync is turned off. $true also sets
# SyncDisabled = 1 (users can no longer sync bookmarks/passwords with their Google account).
$ChromeDisableSync = $false

# User profile folder names to skip during the cleanup (wildcards allowed), e.g. @('kiosk*', 'svc_*')
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\ClearBrowserCachePlatformScript.log"

# ---------------------------------------------------------------------------------------------
# Relaunch in 64-bit PowerShell when started in 32-bit
# ---------------------------------------------------------------------------------------------

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $powershell64) {
        & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

# ---------------------------------------------------------------------------------------------
# Browser definitions
# ---------------------------------------------------------------------------------------------

$BrowserInfo = @{
    Edge    = @{ Process = 'msedge';  PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
                 DataRoot = 'Microsoft\Edge\User Data';   CacheFolders = @('Cache', 'Code Cache', 'GPUCache') }
    Chrome  = @{ Process = 'chrome';  PolicyKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
                 DataRoot = 'Google\Chrome\User Data';    CacheFolders = @('Cache', 'Code Cache', 'GPUCache') }
    Firefox = @{ Process = 'firefox'; PolicyKey = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
                 DataRoot = 'Mozilla\Firefox\Profiles';   CacheFolders = @('cache2') }
}

# ---------------------------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Sets a DWORD policy value unless it already has that value. Returns 'Set' or 'AlreadySet'.
function Set-PolicyDword {
    param([string]$Path, [string]$Name, [int]$Value)
    $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -ne $current -and [int]$current -eq $Value) { return 'AlreadySet' }
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
    return 'Set'
}

# For a Chromium "list" policy stored as values "1", "2", ...: returns the value name to add the
# item under, or $null when the item is already in the list.
function Get-NextListValueName {
    param([hashtable]$Existing, [string]$Item)
    if ($Existing.Values -contains $Item) { return $null }
    $numbers = @($Existing.Keys | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $next = if ($numbers.Count -gt 0) { ($numbers | Measure-Object -Maximum).Maximum + 1 } else { 1 }
    return [string]$next
}

function Add-PolicyListItem {
    param([string]$Path, [string]$Item)
    $existing = @{}
    $key = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($key) { foreach ($name in $key.GetValueNames()) { $existing[$name] = [string]$key.GetValue($name) } }
    $valueName = Get-NextListValueName -Existing $existing -Item $Item
    if (-not $valueName) { return 'AlreadySet' }
    if (-not $key) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $Path -Name $valueName -PropertyType String -Value $Item -Force -ErrorAction Stop | Out-Null
    return 'Set'
}

# Returns the policy changes to make for one browser, as objects the main code applies
function Get-PolicyPlan {
    param([string]$Browser)
    $key = $BrowserInfo[$Browser].PolicyKey
    switch ($Browser) {
        'Edge' {
            @{ Kind = 'Dword'; Path = $key; Name = 'ClearCachedImagesAndFilesOnExit'; Value = 1 }
            if ($ClearAllBrowsingDataOnExit) { @{ Kind = 'Dword'; Path = $key; Name = 'ClearBrowsingDataOnExit'; Value = 1 } }
        }
        'Chrome' {
            @{ Kind = 'List'; Path = "$key\ClearBrowsingDataOnExitList"; Name = 'ClearBrowsingDataOnExitList'; Value = 'cached_images_and_files' }
            if ($ChromeDisableSync) { @{ Kind = 'Dword'; Path = $key; Name = 'SyncDisabled'; Value = 1 } }
        }
        'Firefox' {
            @{ Kind = 'Dword'; Path = "$key\SanitizeOnShutdown"; Name = 'Cache'; Value = 1 }
        }
    }
}

# Real user profiles: LocalPath and SID, without system/service profiles
function Get-UserProfiles {
    Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
        Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) } |
        ForEach-Object { [pscustomobject]@{ Sid = $_.SID; Path = $_.LocalPath; Name = Split-Path -Path $_.LocalPath -Leaf } }
}

# Returns "<SID>|<process name>" for every running browser process, to know whose browser is open
function Get-RunningBrowserOwners {
    $names = @($BrowserInfo.Values | ForEach-Object { "Name='$($_.Process).exe'" }) -join ' OR '
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Filter $names -ErrorAction SilentlyContinue)) {
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($owner -and $owner.Sid) { "$($owner.Sid)|$([IO.Path]::GetFileNameWithoutExtension($process.Name))" }
    }
}

# Cache folders for one browser in one user profile
function Get-BrowserCacheFolders {
    param([string]$ProfilePath, [string]$Browser)
    $info = $BrowserInfo[$Browser]
    $root = Join-Path (Join-Path $ProfilePath 'AppData\Local') $info.DataRoot
    foreach ($browserProfile in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if ($browserProfile.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        foreach ($folder in $info.CacheFolders) {
            $path = Join-Path $browserProfile.FullName $folder
            if (Test-Path -LiteralPath $path) { $path }
        }
    }
}

# Deletes everything inside $Path (keeps $Path itself). Never follows junctions or symbolic links.
# Returns @{ Deleted = <files>; Bytes = <bytes>; InUse = <files skipped> }
function Clear-FolderContents {
    param([string]$Path)
    $result = @{ Deleted = 0; Bytes = [long]0; InUse = 0 }
    $dirs = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $Path))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $entries = $dir.GetFileSystemInfos() } catch { continue }
        foreach ($entry in $entries) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($entry -is [IO.DirectoryInfo]) {
                [void]$dirs.Add($entry)
                $stack.Push($entry)
                continue
            }
            $size = $entry.Length
            try {
                if ($entry.IsReadOnly) { $entry.IsReadOnly = $false }
                $entry.Delete()
                $result.Deleted++
                $result.Bytes += $size
            }
            catch {
                $result.InUse++
            }
        }
    }
    for ($i = $dirs.Count - 1; $i -ge 0; $i--) {
        try {
            if (-not $dirs[$i].EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $dirs[$i].Delete() }
        }
        catch { }
    }
    return $result
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    Write-Log "===== Clear browser cache started on $env:COMPUTERNAME (browsers: $($Browsers -join ', ')) ====="
    $policyFailures = @()
    $policySet = 0

    # 2. Clear-on-close policies
    foreach ($browser in $Browsers) {
        if (-not $BrowserInfo.ContainsKey($browser)) { Write-Log "Unknown browser '$browser' in `$Browsers - skipped."; continue }
        foreach ($plan in @(Get-PolicyPlan -Browser $browser)) {
            try {
                $result = if ($plan.Kind -eq 'List') {
                    Add-PolicyListItem -Path $plan.Path -Item $plan.Value
                } else {
                    Set-PolicyDword -Path $plan.Path -Name $plan.Name -Value $plan.Value
                }
                if ($result -eq 'Set') { $policySet++ }
                Write-Log "$browser policy $($plan.Name) = $($plan.Value): $result"
            }
            catch {
                Write-Log "$browser policy $($plan.Name) failed: $($_.Exception.Message)"
                $policyFailures += "$browser $($plan.Name)"
            }
        }
    }
    if ($Browsers -contains 'Chrome' -and -not $ChromeDisableSync) {
        Write-Log 'Note: Chrome only applies ClearBrowsingDataOnExitList when Chrome Sync is off (SyncDisabled). See README.md.'
    }

    # 3. Existing caches
    $deleted = 0; $bytes = [long]0; $inUse = 0; $skippedOpen = @()
    if ($ClearExistingCache) {
        $running = @(Get-RunningBrowserOwners)
        foreach ($userProfile in @(Get-UserProfiles)) {
            if (Test-Excluded -Name $userProfile.Name) { Write-Log "Profile $($userProfile.Name) is excluded."; continue }

            $folders = @()
            foreach ($browser in @($Browsers | Where-Object { $BrowserInfo.ContainsKey($_) })) {
                if ($running -contains "$($userProfile.Sid)|$($BrowserInfo[$browser].Process)") {
                    Write-Log "Skipped $browser cache for $($userProfile.Name): the browser is open."
                    $skippedOpen += "$($userProfile.Name)/$browser"
                    continue
                }
                $folders += @(Get-BrowserCacheFolders -ProfilePath $userProfile.Path -Browser $browser)
            }
            $inetCache = Join-Path $userProfile.Path 'AppData\Local\Microsoft\Windows\INetCache'
            if (Test-Path -LiteralPath $inetCache) { $folders += $inetCache }

            foreach ($folder in $folders) {
                $r = Clear-FolderContents -Path $folder
                $deleted += $r.Deleted; $bytes += $r.Bytes; $inUse += $r.InUse
                Write-Log ("Cleared {0}: {1} file(s), {2:N1} MB, {3} in use" -f $folder, $r.Deleted, ($r.Bytes / 1MB), $r.InUse)
            }
        }
    }
    else {
        Write-Log 'Existing cache cleanup is off ($ClearExistingCache = $false).'
    }

    # 4. Summary
    $cleanupText = if ($ClearExistingCache) {
        "cleared {0} file(s), {1:N0} MB ({2} in use, {3} open browser(s) skipped)" -f $deleted, ($bytes / 1MB), $inUse, $skippedOpen.Count
    } else { 'existing cache cleanup off' }

    if ($policyFailures.Count -gt 0) {
        $message = "Browser cache: policies FAILED for $($policyFailures -join ', '); $cleanupText. See the log."
        Write-Log $message
        Write-Output $message
        exit 1
    }

    $message = "Browser cache: clear-on-close policies in place ($policySet changed) for $($Browsers -join ', '); $cleanupText."
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    $message = "Clear browser cache failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
