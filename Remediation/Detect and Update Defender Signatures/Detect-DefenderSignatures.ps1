<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects out-of-date Microsoft Defender Antivirus security intelligence (signatures)
    on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Reads Get-MpComputerStatus and reports the device when:
      - The antivirus signatures were last updated more than $MaxSignatureAgeHours hours ago, or
      - Defender itself reports the signatures as out of date (DefenderSignaturesOutOfDate).

    Devices where another antivirus product is active are reported as compliant
    (Defender is not the active antivirus, so its signatures don't matter).
    Devices whose computer name matches $ExcludeList are always reported as compliant.

    Exit codes (read by Intune):
      0 = Signatures are current -> remediation does not run.
      1 = Signatures are out of date -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderSignaturesRemediation.log
#>

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*')
$ExcludeList = @()

# Signatures older than this many hours are out of date
$MaxSignatureAgeHours = 24

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderSignaturesRemediation.log"

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

# Returns the reason the signatures are out of date, or $null when they are current
function Get-SignatureIssue {
    param($LastUpdated, $OutOfDate, [datetime]$Now)
    if ($OutOfDate -eq $true) { return 'Defender reports signatures out of date' }
    if (-not $LastUpdated) { return 'Signatures have never been updated' }
    $ageHours = ($Now - [datetime]$LastUpdated).TotalHours
    if ($ageHours -gt $MaxSignatureAgeHours) { return ("Signatures are {0:N0} hours old (limit {1})" -f $ageHours, $MaxSignatureAgeHours) }
    return $null
}

try {
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Write-Log "$env:COMPUTERNAME is in the exclude list. Skipping."
        Write-Output "$env:COMPUTERNAME is excluded from the Defender signature check."
        exit 0
    }

    $thirdPartyAV = @(Get-ThirdPartyAntivirus)
    if ($thirdPartyAV.Count -gt 0) {
        Write-Log "Another antivirus product is active ($($thirdPartyAV -join ', ')). Skipping."
        Write-Output "Defender is not the active antivirus ($($thirdPartyAV -join ', ')). Skipping."
        exit 0
    }

    $status = Get-MpComputerStatus -ErrorAction Stop
    $issue = Get-SignatureIssue -LastUpdated $status.AntivirusSignatureLastUpdated -OutOfDate $status.DefenderSignaturesOutOfDate -Now (Get-Date)
    $state = "Version $($status.AntivirusSignatureVersion), last updated $($status.AntivirusSignatureLastUpdated)"

    if ($issue) {
        Write-Log "$issue. $state"
        Write-Output "Defender signatures out of date: $issue. $state"
        exit 1
    }

    Write-Log "Signatures are current. $state"
    Write-Output "Defender signatures are current. $state"
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
