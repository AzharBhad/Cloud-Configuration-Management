<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects stale computer Group Policy on hybrid joined (domain joined) Windows 10 / Windows 11 devices.

.DESCRIPTION
    Only applies to domain joined devices (hybrid joined); other devices are reported as compliant.

    Reads the result of the last computer Group Policy refresh from
    HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\
    {00000000-0000-0000-0000-000000000000} and reports the device when:
      - Group Policy has never been applied, or
      - The last successful refresh was more than $MaxAgeHours hours ago, or
      - The last refresh failed (Status is not 0).

    Devices whose computer name matches $ExcludeList are always reported as compliant.

    Exit codes (read by Intune):
      0 = Group Policy is current (or the device is not domain joined).
      1 = Group Policy is stale or failed -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\GroupPolicyRefreshRemediation.log
#>

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*')
$ExcludeList = @()

# Group Policy older than this many hours is stale (Windows refreshes every 90-120 minutes)
$MaxAgeHours = 24

$StateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\GroupPolicyRefreshRemediation.log"

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

# Converts the EndTimeHi / EndTimeLo registry values (a FILETIME split in two DWORDs) to a date
function ConvertFrom-FileTimeParts {
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
    # Registry DWORDs come back as signed Int32, so mask each half to its unsigned 32-bit value
    $fileTime = (([int64]$High -band 4294967295L) -shl 32) -bor ([int64]$Low -band 4294967295L)
    if ($fileTime -le 0) { return $null }
    return [datetime]::FromFileTime($fileTime)
}

# Returns the reason Group Policy is stale, or $null when it is current
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

try {
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Write-Log "$env:COMPUTERNAME is in the exclude list. Skipping."
        Write-Output "$env:COMPUTERNAME is excluded from the Group Policy check."
        exit 0
    }

    if (-not (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain) {
        Write-Log 'Device is not domain joined. Group Policy does not apply.'
        Write-Output 'Device is not domain joined. Group Policy does not apply.'
        exit 0
    }

    $gp = Get-GroupPolicyState
    $issue = Get-GroupPolicyIssue -LastRefresh $gp.LastRefresh -Status $gp.Status -Now (Get-Date)

    if ($issue) {
        Write-Log "Group Policy stale: $issue (last refresh $($gp.LastRefresh), status $($gp.Status))."
        Write-Output "Group Policy stale: $issue."
        exit 1
    }

    Write-Log "Group Policy is current (last refresh $($gp.LastRefresh))."
    Write-Output "Group Policy is current (last refresh $($gp.LastRefresh))."
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
