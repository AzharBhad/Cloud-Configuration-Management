<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Turns Windows Defender Firewall back on.

.DESCRIPTION
    1. Windows Defender Firewall service (mpssvc): sets it to Automatic if disabled and starts it.
       The service is protected by Windows, so this may be refused; that is logged.
    2. For each profile (Domain, Private, Public) that is off:
       - If Group Policy or Intune (MDM) policy turns the profile off, it is SKIPPED and logged.
         Changing the local setting would have no effect - the policy wins. Fix the policy instead.
       - Otherwise: Set-NetFirewallProfile -Enabled True.
    3. Checks the result with the same rules as the detection script.

    Firewall rules are not changed. No restart is needed.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = Firewall is on for all checked profiles and the service is running.
      1 = Something is still off (usually a policy turns it off). See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsFirewallRemediation.log
#>

# Firewall profiles to skip - keep in sync with the detection script
$ExcludeList = @()

# Maximum time to wait for the firewall service to start (seconds)
$ServiceTimeoutSeconds = 120

$Profiles = @('Domain', 'Private', 'Public')

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsFirewallRemediation.log"

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

# Same logic as the detection script
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

# Returns where a policy turns the profile off, or $null when no policy does
function Get-PolicyDisablingProfile {
    param([string]$ProfileName)
    $sources = @{
        'Group Policy' = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\${ProfileName}Profile"
        'Intune (MDM)' = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\Mdm\${ProfileName}Profile"
    }
    foreach ($source in $sources.Keys) {
        $value = (Get-ItemProperty -Path $sources[$source] -Name 'EnableFirewall' -ErrorAction SilentlyContinue).EnableFirewall
        if ($null -ne $value -and [int]$value -eq 0) { return $source }
    }
    return $null
}

function Repair-FirewallService {
    try {
        $service = Get-Service -Name 'mpssvc' -ErrorAction Stop
        if ([string]$service.StartType -eq 'Disabled') {
            Set-Service -Name 'mpssvc' -StartupType Automatic -ErrorAction Stop
            Write-Log 'Set mpssvc start type to Automatic.'
        }
        $service.Refresh()
        if ($service.Status -ne 'Running') {
            Start-Service -Name 'mpssvc' -ErrorAction Stop
            $service.WaitForStatus('Running', (New-TimeSpan -Seconds $ServiceTimeoutSeconds))
            Write-Log 'Started mpssvc.'
        }
    }
    catch {
        Write-Log "Could not repair the mpssvc service: $($_.Exception.Message)"
    }
}

try {
    Write-Log 'Starting Windows Firewall remediation.'

    Repair-FirewallService

    foreach ($name in $Profiles) {
        if (Test-Excluded -Name $name) { continue }
        $fwProfile = Get-NetFirewallProfile -Name $name -PolicyStore ActiveStore -ErrorAction SilentlyContinue
        if (-not $fwProfile -or [string]$fwProfile.Enabled -eq 'True') { continue }

        $policy = Get-PolicyDisablingProfile -ProfileName $name
        if ($policy) {
            Write-Log "Skipped profile ${name}: $policy turns it off (EnableFirewall = 0). Change the policy."
            continue
        }
        try {
            Set-NetFirewallProfile -Name $name -Enabled True -ErrorAction Stop
            Write-Log "Turned on firewall profile $name."
        }
        catch {
            Write-Log "Failed to turn on firewall profile ${name}: $($_.Exception.Message)"
        }
    }

    $issues = @(Get-FirewallIssues)
    if ($issues.Count -gt 0) {
        $message = "Windows Firewall still not fully on: $($issues -join '; ')"
        Write-Log $message
        Write-Output $message
        exit 1
    }

    Write-Log 'Windows Firewall is on for all checked profiles.'
    Write-Output 'Windows Firewall is on for all checked profiles.'
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
