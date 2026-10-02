<#
.SYNOPSIS
    Intune Remediations - detection script.
    Refreshes Group Policy and detects Windows updates that are available but not installed
    on Windows 10 / Windows 11 devices.

.DESCRIPTION
    1. Runs "gpupdate /force" on every run, so the latest Windows Update policy
       (WSUS server, deferrals, etc.) is applied before the scan.
    2. Asks the Windows Update Agent for software updates that are released to this device
       and not installed yet:  IsInstalled=0 and Type='Software' and IsHidden=0
       The scan uses the update source the device is configured for
       (Windows Update, Windows Update for Business or WSUS).
    3. Updates whose title or KB number matches $ExcludeList are ignored.

    Exit codes (read by Intune):
      0 = No pending updates   -> device is compliant, remediation does not run.
      1 = Pending updates found -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdatesRemediation.log
#>

# Updates to ignore - KB numbers or titles, wildcards allowed, e.g. @('KB5034441', '*Preview*')
$ExcludeList = @()

# Maximum time to wait for gpupdate (minutes)
$GPUpdateTimeoutMinutes = 10

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdatesRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param($Update)
    foreach ($pattern in $ExcludeList) {
        if ($Update.Title -like $pattern) { return $true }
        foreach ($kb in $Update.KBArticleIDs) {
            if ("KB$kb" -like $pattern) { return $true }
        }
    }
    return $false
}

function Get-UpdateLabel {
    param($Update)
    $kbs = @($Update.KBArticleIDs | ForEach-Object { "KB$_" }) -join ','
    if ($kbs) { return "$kbs - $($Update.Title)" }
    return $Update.Title
}

function Invoke-GPUpdate {
    # "echo N" answers the log off / restart prompt gpupdate can show, so it never waits for input
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList '/c echo N | gpupdate.exe /force' -PassThru -WindowStyle Hidden

    if (-not $process.WaitForExit($GPUpdateTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { }
        Write-Log "gpupdate /force timed out after $GPUpdateTimeoutMinutes minutes."
        return
    }
    Write-Log "gpupdate /force finished (exit code $($process.ExitCode))."
}

function Get-PendingUpdates {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    $pending = @()
    foreach ($update in $result.Updates) {
        if (-not (Test-Excluded -Update $update)) { $pending += $update }
    }
    return ,$pending
}

try {
    Invoke-GPUpdate

    $pending = Get-PendingUpdates

    if ($pending.Count -gt 0) {
        $labels = @($pending | ForEach-Object { Get-UpdateLabel -Update $_ })
        Write-Log "Found $($pending.Count) pending update(s): $($labels -join '; ')"
        # Intune shows the last line of output in the admin center (max 2048 characters)
        $summary = "Pending updates ({0}): {1}" -f $pending.Count, ($labels -join '; ')
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Log 'No pending updates.'
    Write-Output 'No pending updates.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
