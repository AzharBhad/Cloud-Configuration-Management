<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects a disabled Windows Defender Firewall on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Reports the device when:
      - Any firewall profile (Domain, Private, Public) is turned off in the effective
        (active) firewall settings, or
      - The Windows Defender Firewall service (mpssvc) is not running or is disabled.

    Profiles listed in $ExcludeList are not checked.

    Exit codes (read by Intune):
      0 = Firewall is on for all checked profiles and the service is running.
      1 = Firewall is off for a profile, or the service is not running -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsFirewallRemediation.log
#>

# Firewall profiles to skip (Domain, Private, Public; wildcards allowed)
$ExcludeList = @()

$Profiles = @('Domain', 'Private', 'Public')

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsFirewallRemediation.log"

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

function Get-FirewallIssues {
    $service = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
    if (-not $service) {
        'Service mpssvc: not found'
    }
    elseif ($service.Status -ne 'Running' -or [string]$service.StartType -eq 'Disabled') {
        "Service mpssvc: $($service.Status), $($service.StartType)"
    }

    foreach ($name in $Profiles) {
        if (Test-Excluded -Name $name) { continue }
        $fwProfile = Get-NetFirewallProfile -Name $name -PolicyStore ActiveStore -ErrorAction SilentlyContinue
        if ($fwProfile -and [string]$fwProfile.Enabled -ne 'True') {
            "Profile ${name}: off"
        }
    }
}

try {
    $issues = @(Get-FirewallIssues)

    if ($issues.Count -gt 0) {
        Write-Log "Firewall issues: $($issues -join '; ')"
        Write-Output "Windows Firewall not fully on: $($issues -join '; ')"
        exit 1
    }

    Write-Log 'Windows Firewall is on for all checked profiles.'
    Write-Output 'Windows Firewall is on for all checked profiles.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
