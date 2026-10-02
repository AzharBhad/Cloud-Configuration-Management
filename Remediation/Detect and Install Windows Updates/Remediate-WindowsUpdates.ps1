<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Refreshes Group Policy and installs the pending Windows updates found by
    Detect-WindowsUpdates.ps1.

.DESCRIPTION
    1. Runs "gpupdate /force" so the latest Windows Update policy is applied.
    2. Scans for software updates that are not installed (same query and $ExcludeList
       as the detection script).
    3. Skips updates that need user input, accepts update license terms (EULAs),
       then downloads and installs the rest silently.

    The scan, download and install run in a background job with a time limit
    ($UpdateTimeoutMinutes) so the script finishes inside Intune's 60-minute limit.
    Updates not installed in time are picked up on the next run.

    The device is never restarted. Updates that need a restart are reported as
    "restart pending" and finish installing at the user's next restart.

    The schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All pending updates installed (a restart may still be needed).
      1 = One or more updates were not installed, or gpupdate failed.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdatesRemediation.log
#>

# Updates to ignore - KB numbers or titles, wildcards allowed - keep in sync with the detection script
$ExcludeList = @()

# Maximum time to wait for gpupdate (minutes)
$GPUpdateTimeoutMinutes = 10

# Maximum time for scanning, downloading and installing updates (minutes)
$UpdateTimeoutMinutes = 40

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdatesRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Invoke-GPUpdate {
    # "echo N" answers the log off / restart prompt gpupdate can show, so it never waits for input
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList '/c echo N | gpupdate.exe /force' -PassThru -WindowStyle Hidden

    if (-not $process.WaitForExit($GPUpdateTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { }
        Write-Log "gpupdate /force timed out after $GPUpdateTimeoutMinutes minutes."
        return $false
    }
    Write-Log "gpupdate /force finished (exit code $($process.ExitCode))."
    return ($process.ExitCode -eq 0)
}

# Runs in a background job, so it re-creates the Windows Update objects itself.
# The matching logic (Test-Excluded) is the same as in the detection script.
$InstallUpdatesJob = {
    param([string[]]$ExcludeList)

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

    $results = @()
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($update in $searchResult.Updates) {
        $label = Get-UpdateLabel -Update $update
        if (Test-Excluded -Update $update) {
            continue
        }
        if ($update.InstallationBehavior.CanRequestUserInput) {
            $results += [pscustomobject]@{ Update = $label; Status = 'Skipped'; Detail = 'Needs user input' }
            continue
        }
        if (-not $update.EulaAccepted) { $update.AcceptEula() }
        [void]$toInstall.Add($update)
    }

    if ($toInstall.Count -eq 0) {
        return $results
    }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    [void]$downloader.Download()

    $downloaded = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($update in $toInstall) {
        if ($update.IsDownloaded) {
            [void]$downloaded.Add($update)
        }
        else {
            $results += [pscustomobject]@{ Update = (Get-UpdateLabel -Update $update); Status = 'Failed'; Detail = 'Download failed' }
        }
    }

    if ($downloaded.Count -eq 0) {
        return $results
    }

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $downloaded
    $installResult = $installer.Install()

    # Result codes: 2 = Succeeded, 3 = Succeeded with errors, 4 = Failed, 5 = Aborted
    for ($i = 0; $i -lt $downloaded.Count; $i++) {
        $update = $downloaded.Item($i)
        $itemResult = $installResult.GetUpdateResult($i)
        $label = Get-UpdateLabel -Update $update
        if ($itemResult.ResultCode -in 2, 3) {
            $detail = if ($itemResult.RebootRequired) { 'Installed, restart pending' } else { 'Installed' }
            $results += [pscustomobject]@{ Update = $label; Status = 'Installed'; Detail = $detail }
        }
        else {
            $results += [pscustomobject]@{
                Update = $label
                Status = 'Failed'
                Detail = ('Result code {0}, HResult 0x{1:X8}' -f $itemResult.ResultCode, $itemResult.HResult)
            }
        }
    }

    return $results
}

try {
    Write-Log 'Starting Windows update remediation.'
    $failed = @()
    $restartPending = @()

    if (-not (Invoke-GPUpdate)) {
        $failed += 'gpupdate /force'
    }

    $job = Start-Job -ScriptBlock $InstallUpdatesJob -ArgumentList (, [string[]]$ExcludeList)
    if (-not (Wait-Job -Job $job -Timeout ($UpdateTimeoutMinutes * 60))) {
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        Write-Log "Update install timed out after $UpdateTimeoutMinutes minutes. Remaining updates will be installed on the next run."
        $failed += "Update install timed out after $UpdateTimeoutMinutes minutes"
    }
    else {
        $jobError = $null
        $jobState = $job.State
        $jobReason = $job.ChildJobs[0].JobStateInfo.Reason
        $results = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable jobError)
        Remove-Job -Job $job -Force
        foreach ($err in $jobError) {
            Write-Log "Windows Update error: $($err.Exception.Message)"
            $failed += "Windows Update error: $($err.Exception.Message)"
        }
        if ($jobState -eq 'Failed' -and $jobError.Count -eq 0) {
            $message = if ($jobReason) { $jobReason.Message } else { 'unknown error' }
            Write-Log "Windows Update job failed: $message"
            $failed += "Windows Update job failed: $message"
        }

        foreach ($result in $results) {
            Write-Log "$($result.Status): $($result.Update) ($($result.Detail))"
            if ($result.Status -ne 'Installed') { $failed += "$($result.Update) ($($result.Detail))" }
        }

        $installed = @($results | Where-Object { $_.Status -eq 'Installed' })
        $restartPending = @($installed | Where-Object { $_.Detail -like '*restart pending*' })
        if ($installed.Count -gt 0) {
            Write-Log "Installed $($installed.Count) update(s), $($restartPending.Count) waiting for a restart."
        }
    }

    if ($failed.Count -gt 0) {
        $summary = "Windows update remediation incomplete: $($failed -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Log $summary
        Write-Output $summary
        exit 1
    }

    $summary = 'All pending Windows updates installed.'
    if ($restartPending.Count -gt 0) { $summary += " $($restartPending.Count) update(s) need a restart to finish." }
    Write-Log $summary
    Write-Output $summary
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
