<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Restores registry security settings that differ from the required baseline.

.DESCRIPTION
    For each setting in $Baseline that is missing or different, creates the registry key if needed
    and writes the required value (New-ItemProperty -Force). Then checks again.

    Some settings only take effect after a restart (Reboot = $true in $Baseline, for example
    LsaRunAsPPL, SMBv1ServerOff and UACOn). The script never restarts the device; the output lists
    the settings waiting for a restart.

    If Group Policy or Intune sets one of these values differently, it will be changed back at the
    next policy refresh and the device will be reported again. Fix the policy, or add the setting
    to $ExcludeList.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All settings now match the baseline (a restart may still be needed).
      1 = One or more settings could not be written. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RegistrySecurityRemediation.log
#>

# Settings to skip, matched against "<Path>\<Name>" or the setting's Id (wildcards allowed),
# e.g. @('LsaRunAsPPL', '*\LanmanServer\*') - keep in sync with the detection script
$ExcludeList = @()

# Required registry security settings - keep in sync with the detection script
# Id: short name used in logs and $ExcludeList. Reboot: $true when the setting takes effect after a restart.
$Baseline = @(
    @{ Id = 'NTLMv2Only';            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LmCompatibilityLevel'; Type = 'DWord'; Value = 5; Reboot = $false
       Description = 'Send NTLMv2 responses only; refuse LM and NTLM' }
    @{ Id = 'NoLMHash';              Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'NoLMHash'; Type = 'DWord'; Value = 1; Reboot = $false
       Description = 'Do not store LAN Manager password hashes' }
    @{ Id = 'RestrictAnonymous';     Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RestrictAnonymous'; Type = 'DWord'; Value = 1; Reboot = $false
       Description = 'Do not allow anonymous enumeration of shares' }
    @{ Id = 'RestrictAnonymousSAM';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RestrictAnonymousSAM'; Type = 'DWord'; Value = 1; Reboot = $false
       Description = 'Do not allow anonymous enumeration of SAM accounts' }
    @{ Id = 'LsaRunAsPPL';           Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RunAsPPL'; Type = 'DWord'; Value = 1; Reboot = $true
       Description = 'Run LSA as a protected process (credential theft protection)' }
    @{ Id = 'WDigestOff';            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Type = 'DWord'; Value = 0; Reboot = $false
       Description = 'Do not keep plain-text passwords in memory for WDigest' }
    @{ Id = 'SMBv1ServerOff';        Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Name = 'SMB1'; Type = 'DWord'; Value = 0; Reboot = $true
       Description = 'Turn off the SMBv1 server' }
    @{ Id = 'AutoRunOff';            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun'; Type = 'DWord'; Value = 255; Reboot = $false
       Description = 'Turn off AutoRun for all drive types' }
    @{ Id = 'UACOn';                 Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableLUA'; Type = 'DWord'; Value = 1; Reboot = $true
       Description = 'User Account Control is on' }
    @{ Id = 'LLMNROff';              Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Name = 'EnableMulticast'; Type = 'DWord'; Value = 0; Reboot = $false
       Description = 'Turn off LLMNR name resolution (spoofing protection)' }
)

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\RegistrySecurityRemediation.log"

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

# Returns the settings whose current value differs from the baseline
function Get-RegistryDrift {
    param([scriptblock]$ReadValue)
    foreach ($setting in $Baseline) {
        if ((Test-Excluded -Name $setting.Id) -or (Test-Excluded -Name "$($setting.Path)\$($setting.Name)")) { continue }
        $current = & $ReadValue $setting.Path $setting.Name
        if ($null -eq $current -or "$current" -ne "$($setting.Value)") {
            [pscustomobject]@{ Setting = $setting; Current = $current }
        }
    }
}

function Read-RegistryValue {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($item) { return $item.$Name }
    return $null
}

function Format-Drift {
    param($Drift)
    $current = if ($null -eq $Drift.Current) { 'missing' } else { $Drift.Current }
    return "$($Drift.Setting.Id) ($($Drift.Setting.Name) = $current, required $($Drift.Setting.Value))"
}

try {
    Write-Log 'Starting registry security settings remediation.'
    $drift = @(Get-RegistryDrift -ReadValue ${function:Read-RegistryValue})
    $failed = @()
    $reboot = @()

    foreach ($item in $drift) {
        $setting = $item.Setting
        try {
            if (-not (Test-Path -Path $setting.Path)) {
                New-Item -Path $setting.Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -Path $setting.Path -Name $setting.Name -PropertyType $setting.Type -Value $setting.Value -Force -ErrorAction Stop | Out-Null
            Write-Log "Set $(Format-Drift -Drift $item) -> $($setting.Value). $($setting.Description)."
            if ($setting.Reboot) { $reboot += $setting.Id }
        }
        catch {
            Write-Log "Failed to set $($setting.Id): $($_.Exception.Message)"
            $failed += $setting.Id
        }
    }

    $remaining = @(Get-RegistryDrift -ReadValue ${function:Read-RegistryValue})
    $rebootNote = if ($reboot.Count -gt 0) { " Restart needed for: $($reboot -join ', ')." } else { '' }

    if ($remaining.Count -gt 0) {
        $message = "Restored $($drift.Count - $remaining.Count) of $($drift.Count) setting(s). Still different: $((@($remaining | ForEach-Object { Format-Drift -Drift $_ })) -join '; ').$rebootNote"
        Write-Log $message
        Write-Output $message
        exit 1
    }

    $message = "Restored $($drift.Count) registry security setting(s).$rebootNote"
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
