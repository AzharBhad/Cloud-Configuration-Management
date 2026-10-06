<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects when temporary files and caches take up too much disk space on
    Windows 10 / Windows 11 devices.

.DESCRIPTION
    Adds up the size of files older than $MinFileAgeDays days in these locations:
      - Windows temp folder                  (C:\Windows\Temp)
      - Each user's temp folder              (C:\Users\<user>\AppData\Local\Temp)
      - Each user's Internet cache           (...\AppData\Local\Microsoft\Windows\INetCache)
      - Each user's Edge and Chrome caches   (...\User Data\<profile>\Cache and Code Cache)
      - Each user's crash dumps              (...\AppData\Local\CrashDumps)
      - Windows Update download cache        (C:\Windows\SoftwareDistribution\Download)
      - Delivery Optimization cache

    Reports the device when the total is more than $ThresholdMB MB.
    Folders matching $ExcludeList are not counted. Junctions and symbolic links are never followed.

    Exit codes (read by Intune):
      0 = Temporary files are below the threshold.
      1 = Temporary files are above the threshold -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TempFilesRemediation.log
#>

# Folders to skip (wildcards allowed), e.g. @('C:\Users\svc_*\*', '*\Chrome\*')
$ExcludeList = @()

# Only files older than this many days count (and are removed)
$MinFileAgeDays = 7

# Report the device when old temporary files add up to more than this (MB)
$ThresholdMB = 1024

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\TempFilesRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

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

# Returns files under $Path older than $Cutoff. Never follows junctions or symbolic links.
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

try {
    $cutoff = (Get-Date).AddDays(-$MinFileAgeDays)
    $totalBytes = [long]0
    $details = @()
    foreach ($folder in Get-CleanupFolders) {
        $bytes = [long]0
        foreach ($file in Get-OldFiles -Path $folder -Cutoff $cutoff) { $bytes += $file.Length }
        $totalBytes += $bytes
        if ($bytes -ge 100MB) { $details += ("{0} {1:N0} MB" -f $folder, ($bytes / 1MB)) }
    }

    $totalMB = [math]::Round($totalBytes / 1MB)
    Write-Log "Old temporary files: $totalMB MB (threshold $ThresholdMB MB). Largest: $($details -join '; ')"

    if ($totalMB -gt $ThresholdMB) {
        $summary = "Temporary files use $totalMB MB (threshold $ThresholdMB MB). Largest: $($details -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Output "Temporary files use $totalMB MB (threshold $ThresholdMB MB)."
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
