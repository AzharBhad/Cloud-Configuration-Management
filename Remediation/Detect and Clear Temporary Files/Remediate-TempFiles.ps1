<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Deletes old temporary files and caches found by Detect-TempFiles.ps1.

.DESCRIPTION
    Deletes files older than $MinFileAgeDays days from the same locations as the detection script,
    then removes folders that are left empty. Files in use are skipped silently - that is normal.
    Junctions and symbolic links are never followed, so nothing outside these folders is touched.

    The Delivery Optimization cache is cleared with Delete-DeliveryOptimizationCache.

    Stops after $TimeoutMinutes minutes so the script finishes inside Intune's 60-minute limit;
    the rest is cleaned on the next run. No restart is needed.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = Old temporary files are now below the threshold.
      1 = Still above the threshold (files in use, or the time limit was reached). See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TempFilesRemediation.log
#>

# Folders to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Only files older than this many days are removed - keep in sync with the detection script
$MinFileAgeDays = 7

# Threshold in MB - keep in sync with the detection script
$ThresholdMB = 1024

# Stop deleting after this many minutes
$TimeoutMinutes = 40

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\TempFilesRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Same folders as the detection script
function Get-CleanupFolders {
    $folders = @(
        "$env:SystemRoot\Temp",
        "$env:SystemRoot\SoftwareDistribution\Download",
        "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
    )
    $profileRoot = Split-Path -Path $env:PUBLIC -Parent
    foreach ($userProfile in @(Get-ChildItem -Path $profileRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($userProfile.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $local = Join-Path $userProfile.FullName 'AppData\Local'
        $folders += Join-Path $local 'Temp'
        $folders += Join-Path $local 'Microsoft\Windows\INetCache'
        $folders += Join-Path $local 'CrashDumps'
        foreach ($browser in 'Microsoft\Edge\User Data', 'Google\Chrome\User Data') {
            foreach ($browserProfile in @(Get-ChildItem -Path (Join-Path $local $browser) -Directory -ErrorAction SilentlyContinue)) {
                $folders += Join-Path $browserProfile.FullName 'Cache'
                $folders += Join-Path $browserProfile.FullName 'Code Cache'
            }
        }
    }
    return @($folders | Where-Object { (Test-Path -LiteralPath $_) -and -not (Test-Excluded -Name $_) })
}

# Same logic as the detection script
function Get-OldFiles {
    param([string]$Path, [datetime]$Cutoff)
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $Path))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $entries = $dir.GetFileSystemInfos() } catch { continue }
        foreach ($entry in $entries) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($entry -is [IO.DirectoryInfo]) {
                if (-not (Test-Excluded -Name $entry.FullName)) { $stack.Push($entry) }
            }
            elseif ($entry.LastWriteTime -lt $Cutoff) {
                $entry
            }
        }
    }
}

# Removes empty sub-folders (deepest first), keeping the top folder itself
function Remove-EmptyFolders {
    param([string]$Path)
    $dirs = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $Path))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $children = $dir.GetDirectories() } catch { continue }
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            [void]$dirs.Add($child)
            $stack.Push($child)
        }
    }
    for ($i = $dirs.Count - 1; $i -ge 0; $i--) {
        try {
            if (-not $dirs[$i].EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $dirs[$i].Delete() }
        }
        catch { }
    }
}

function Get-OldFilesTotalMB {
    param([datetime]$Cutoff)
    $bytes = [long]0
    foreach ($folder in Get-CleanupFolders) {
        foreach ($file in Get-OldFiles -Path $folder -Cutoff $Cutoff) { $bytes += $file.Length }
    }
    return [math]::Round($bytes / 1MB)
}

try {
    Write-Log 'Starting temporary file cleanup.'
    $cutoff = (Get-Date).AddDays(-$MinFileAgeDays)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $freedBytes = [long]0
    $deleted = 0
    $inUse = 0
    $timedOut = $false

    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        Write-Log 'Cleared the Delivery Optimization cache.'
    }
    catch {
        Write-Log "Could not clear the Delivery Optimization cache: $($_.Exception.Message)"
    }

    foreach ($folder in Get-CleanupFolders) {
        foreach ($file in Get-OldFiles -Path $folder -Cutoff $cutoff) {
            if ((Get-Date) -gt $deadline) { $timedOut = $true; break }
            $size = $file.Length
            try {
                if ($file.IsReadOnly) { $file.IsReadOnly = $false }
                $file.Delete()
                $freedBytes += $size
                $deleted++
            }
            catch {
                $inUse++
            }
        }
        Remove-EmptyFolders -Path $folder
        if ($timedOut) { break }
    }

    $freedMB = [math]::Round($freedBytes / 1MB)
    Write-Log "Deleted $deleted file(s), freed $freedMB MB. Skipped $inUse file(s) in use."
    if ($timedOut) { Write-Log "Stopped after $TimeoutMinutes minutes. The rest is cleaned on the next run." }

    $remainingMB = Get-OldFilesTotalMB -Cutoff $cutoff
    if ($remainingMB -gt $ThresholdMB) {
        $message = "Freed $freedMB MB, but $remainingMB MB of old temporary files remain (threshold $ThresholdMB MB)."
        Write-Log $message
        Write-Output $message
        exit 1
    }

    $message = "Freed $freedMB MB of temporary files. $remainingMB MB remain (threshold $ThresholdMB MB)."
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
