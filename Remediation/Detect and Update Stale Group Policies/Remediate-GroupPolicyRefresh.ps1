<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Refreshes stale computer Group Policy on hybrid joined (domain joined) devices.

.DESCRIPTION
    1. Checks a domain controller can be reached (nltest /dsgetdc:<domain>). If not - for example
       the device is off the corporate network and not on VPN - it is SKIPPED; Group Policy can't
       be downloaded without a domain controller. The next run tries again.
    2. Runs "gpupdate /target:computer /force" (the "N" answer is piped in so it never waits for
       a log off / restart prompt). Stopped after $GPUpdateTimeoutMinutes minutes.
    3. Checks the result with the same rules as the detection script.

    User Group Policy refreshes on its own at the user's next sign-in or refresh cycle.
    The device is not restarted, even if a policy asks for one.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = Group Policy refreshed (or the device is not domain joined).
      1 = Domain controller not reachable, or the refresh failed. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\GroupPolicyRefreshRemediation.log
#>

# Computer names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Group Policy older than this many hours is stale - keep in sync with the detection script
$MaxAgeHours = 24

# Maximum time for gpupdate and nltest (minutes)
$GPUpdateTimeoutMinutes = 10

$StateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\GroupPolicyRefreshRemediation.log"

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

function ConvertFrom-FileTimeParts {
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
    # Registry DWORDs come back as signed Int32, so mask each half to its unsigned 32-bit value
    $fileTime = (([int64]$High -band 4294967295L) -shl 32) -bor ([int64]$Low -band 4294967295L)
    if ($fileTime -le 0) { return $null }
    return [datetime]::FromFileTime($fileTime)
}

# Same logic as the detection script
function Get-GroupPolicyIssue {
    param($LastRefresh, $Status, [datetime]$Now)
    if (-not $LastRefresh) { return 'Group Policy has never been applied' }
    if ($null -ne $Status -and [int]$Status -ne 0) { return ("Last refresh failed (status {0})" -f $Status) }
    $ageHours = ($Now - [datetime]$LastRefresh).TotalHours
    if ($ageHours -gt $MaxAgeHours) { return ("Last refresh was {0:N0} hours ago (limit {1})" -f $ageHours, $MaxAgeHours) }
    return $null
}

function Get-GroupPolicyState {
    $values = Get-ItemProperty -Path $StateKey -ErrorAction SilentlyContinue
    if (-not $values) { return @{ LastRefresh = $null; Status = $null } }
    return @{
        LastRefresh = ConvertFrom-FileTimeParts -High $values.EndTimeHi -Low $values.EndTimeLo
        Status      = $values.Status
    }
}

# Runs a command line through cmd.exe with a timeout. Returns the exit code, or $null on timeout.
function Invoke-WithTimeout {
    param([string]$CommandLine)
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c $CommandLine" `
        -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($GPUpdateTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { }
        return $null
    }
    return $process.ExitCode
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    Write-Log 'Starting Group Policy refresh.'

    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Remediation 0 "$env:COMPUTERNAME is excluded from the Group Policy check."
    }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $computer.PartOfDomain) {
        Exit-Remediation 0 'Device is not domain joined. Group Policy does not apply.'
    }

    $dcResult = Invoke-WithTimeout -CommandLine "nltest.exe /dsgetdc:$($computer.Domain) >nul 2>&1"
    if ($dcResult -ne 0) {
        Exit-Remediation 1 "Skipped: no domain controller for $($computer.Domain) is reachable (nltest exit code $dcResult). The device may be off the corporate network or VPN."
    }
    Write-Log "Domain controller for $($computer.Domain) is reachable."

    $gpResult = Invoke-WithTimeout -CommandLine 'echo N | gpupdate.exe /target:computer /force'
    if ($null -eq $gpResult) {
        Write-Log "gpupdate timed out after $GPUpdateTimeoutMinutes minutes."
    }
    else {
        Write-Log "gpupdate /target:computer /force finished (exit code $gpResult)."
    }

    $gp = Get-GroupPolicyState
    $issue = Get-GroupPolicyIssue -LastRefresh $gp.LastRefresh -Status $gp.Status -Now (Get-Date)
    if ($issue) {
        Exit-Remediation 1 "Group Policy still stale after gpupdate: $issue. Check the GroupPolicy event log."
    }
    Exit-Remediation 0 "Group Policy refreshed (last refresh $($gp.LastRefresh))."
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
