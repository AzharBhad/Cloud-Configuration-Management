<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects registry security settings that differ from the required baseline on
    Windows 10 / Windows 11 devices.

.DESCRIPTION
    Compares each setting in $Baseline with the value in the registry and reports the device when
    any value is missing or different. The default baseline hardens credential handling and
    legacy protocols:
      NTLMv2Only, NoLMHash, RestrictAnonymous, RestrictAnonymousSAM, LsaRunAsPPL, WDigestOff,
      SMBv1ServerOff, AutoRunOff, UACOn, LLMNROff
    Edit $Baseline to match your organization's security standard.

    Settings whose Id or "<Path>\<Name>" matches $ExcludeList are not checked.

    Exit codes (read by Intune):
      0 = All settings match the baseline.
      1 = One or more settings differ -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RegistrySecurityRemediation.log
#>

# Settings to skip, matched against "<Path>\<Name>" or the setting's Id (wildcards allowed),
# e.g. @('LsaRunAsPPL', '*\LanmanServer\*')
$ExcludeList = @()

# Required registry security settings
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
    $drift = @(Get-RegistryDrift -ReadValue ${function:Read-RegistryValue})

    if ($drift.Count -gt 0) {
        $labels = @($drift | ForEach-Object { Format-Drift -Drift $_ })
        Write-Log "Found $($drift.Count) setting(s) that differ from the baseline: $($labels -join '; ')"
        $summary = "Registry security settings not as required ($($drift.Count)): $($labels -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Log 'All registry security settings match the baseline.'
    Write-Output 'All registry security settings match the baseline.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
