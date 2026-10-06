<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Updates Microsoft Defender Antivirus security intelligence (signatures).

.DESCRIPTION
    1. Runs "MpCmdRun.exe -SignatureUpdate", which uses the update sources set for the device
       (Windows Update / WSUS / file share / Microsoft Malware Protection Center).
    2. If that fails, runs "MpCmdRun.exe -SignatureUpdate -MMPC" to download directly from
       the Microsoft Malware Protection Center.
    3. Checks the signatures are now current (same rules as the detection script).

    Each update attempt is stopped after $UpdateTimeoutMinutes minutes, so the script finishes
    well inside Intune's 60-minute limit. No restart is needed.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = Signatures are current.
      1 = Signatures could not be updated. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderSignaturesRemediation.log
#>

# Computer names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Signatures older than this many hours are out of date - keep in sync with the detection script
$MaxSignatureAgeHours = 24

# Maximum time for each update attempt (minutes)
$UpdateTimeoutMinutes = 15

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderSignaturesRemediation.log"

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

function Test-ProductEnabled {
    param([int]$ProductState)
    return ((($ProductState -shr 8) -band 0xFF) -in 0x10, 0x11)
}

function Get-ThirdPartyAntivirus {
    $products = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction SilentlyContinue
    foreach ($product in $products) {
        if ($product.displayName -notlike '*Defender*' -and (Test-ProductEnabled -ProductState $product.productState)) {
            $product.displayName
        }
    }
}

function Get-SignatureIssue {
    param($LastUpdated, $OutOfDate, [datetime]$Now)
    if ($OutOfDate -eq $true) { return 'Defender reports signatures out of date' }
    if (-not $LastUpdated) { return 'Signatures have never been updated' }
    $ageHours = ($Now - [datetime]$LastUpdated).TotalHours
    if ($ageHours -gt $MaxSignatureAgeHours) { return ("Signatures are {0:N0} hours old (limit {1})" -f $ageHours, $MaxSignatureAgeHours) }
    return $null
}

function Invoke-SignatureUpdate {
    param([string]$Arguments)
    $mpCmdRun = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    Write-Log "Running MpCmdRun.exe $Arguments"
    $process = Start-Process -FilePath $mpCmdRun -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($UpdateTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { }
        Write-Log "MpCmdRun.exe $Arguments timed out after $UpdateTimeoutMinutes minutes."
        return $false
    }
    Write-Log "MpCmdRun.exe $Arguments finished (exit code $($process.ExitCode))."
    return ($process.ExitCode -eq 0)
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    Write-Log 'Starting Defender signature update.'

    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Remediation 0 "$env:COMPUTERNAME is excluded from the Defender signature check."
    }
    $thirdPartyAV = @(Get-ThirdPartyAntivirus)
    if ($thirdPartyAV.Count -gt 0) {
        Exit-Remediation 0 "Defender is not the active antivirus ($($thirdPartyAV -join ', ')). Skipping."
    }

    if (-not (Invoke-SignatureUpdate -Arguments '-SignatureUpdate')) {
        Write-Log 'Update from the configured sources failed. Trying the Microsoft Malware Protection Center.'
        [void](Invoke-SignatureUpdate -Arguments '-SignatureUpdate -MMPC')
    }

    $status = Get-MpComputerStatus -ErrorAction Stop
    $issue = Get-SignatureIssue -LastUpdated $status.AntivirusSignatureLastUpdated -OutOfDate $status.DefenderSignaturesOutOfDate -Now (Get-Date)
    $state = "Version $($status.AntivirusSignatureVersion), last updated $($status.AntivirusSignatureLastUpdated)"

    if ($issue) {
        Exit-Remediation 1 "Defender signatures still out of date: $issue. $state"
    }
    Exit-Remediation 0 "Defender signatures updated. $state"
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
