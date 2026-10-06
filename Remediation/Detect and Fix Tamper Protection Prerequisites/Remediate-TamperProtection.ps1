<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Fixes the missing Microsoft Defender tamper protection prerequisites found by
    Detect-TamperProtection.ps1.

.DESCRIPTION
    Fixes:
      DefenderServiceNotRunning  -> Start-Service WinDefend (wait up to $ServiceTimeoutSeconds)
      PolicyDisablesDefender:*   -> Removes DisableAntiSpyware / DisableAntiVirus from
                                    HKLM\SOFTWARE\Policies\Microsoft\Windows Defender.
                                    If a Group Policy sets it, it comes back at the next policy
                                    refresh - fix the GPO as well.
      RealTimeProtectionOff      -> Set-MpPreference -DisableRealtimeMonitoring $false
      CloudProtectionOff         -> Set-MpPreference -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples
      EngineTooOld               -> MpCmdRun.exe -SignatureUpdate (engine updates come with signatures)

    Not fixed (Skipped and logged):
      PlatformTooOld             -> the Defender platform is updated through Windows Update
                                    (KB4052623); install it from Windows Update.
      NotOnboardedToDefenderForEndpoint -> onboard the device through Intune EDR policy
                                    (Endpoint security > Endpoint detection and response).

    Tamper protection itself is then turned on by your Intune antivirus policy
    (Windows Security experience profile) or the Defender portal. No restart is needed.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All prerequisites are met.
      1 = One or more prerequisites are still missing. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TamperProtectionRemediation.log
#>

# Checks to skip by name (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

$MinimumPlatformVersion = [version]'4.18.2010.7'
$MinimumEngineVersion = [version]'1.1.17600.5'
$DefenderPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'

# Maximum time to wait for the Defender service to start (seconds)
$ServiceTimeoutSeconds = 120

# Maximum time for the engine update (minutes)
$UpdateTimeoutMinutes = 15

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\TamperProtectionRemediation.log"

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

function Test-VersionBelow {
    param([string]$Version, [version]$Minimum)
    $parsed = $null
    if (-not [version]::TryParse($Version, [ref]$parsed)) { return $true }
    return ($parsed -lt $Minimum)
}

# Same logic as the detection script
function Get-PrerequisiteIssues {
    param($State)
    $issues = @()
    if ($State.ServiceStatus -ne 'Running') { $issues += 'DefenderServiceNotRunning' }
    foreach ($name in 'DisableAntiSpyware', 'DisableAntiVirus') {
        if ($State.Policies[$name] -eq 1) { $issues += "PolicyDisablesDefender:$name" }
    }
    if ($State.RealTimeProtectionEnabled -ne $true) { $issues += 'RealTimeProtectionOff' }
    if ($State.MAPSReporting -eq 0) { $issues += 'CloudProtectionOff' }
    if (Test-VersionBelow -Version $State.PlatformVersion -Minimum $MinimumPlatformVersion) { $issues += "PlatformTooOld:$($State.PlatformVersion)" }
    if (Test-VersionBelow -Version $State.EngineVersion -Minimum $MinimumEngineVersion) { $issues += "EngineTooOld:$($State.EngineVersion)" }
    if (-not $State.Onboarded) { $issues += 'NotOnboardedToDefenderForEndpoint' }
    return @($issues | Where-Object { -not (Test-Excluded -Name $_) })
}

function Get-DeviceState {
    $service = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $preference = Get-MpPreference -ErrorAction SilentlyContinue
    $policyValues = Get-ItemProperty -Path $DefenderPolicyKey -ErrorAction SilentlyContinue
    $onboarding = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' -Name 'OnboardingState' -ErrorAction SilentlyContinue

    return @{
        ServiceStatus             = if ($service) { [string]$service.Status } else { 'NotFound' }
        Policies                  = @{
            DisableAntiSpyware = if ($policyValues) { $policyValues.DisableAntiSpyware } else { $null }
            DisableAntiVirus   = if ($policyValues) { $policyValues.DisableAntiVirus } else { $null }
        }
        RealTimeProtectionEnabled = if ($status) { $status.RealTimeProtectionEnabled } else { $null }
        MAPSReporting             = if ($preference) { [int]$preference.MAPSReporting } else { $null }
        PlatformVersion           = if ($status) { [string]$status.AMProductVersion } else { '' }
        EngineVersion             = if ($status) { [string]$status.AMEngineVersion } else { '' }
        Onboarded                 = [bool]($onboarding -and $onboarding.OnboardingState -eq 1)
        IsTamperProtected         = if ($status) { $status.IsTamperProtected } else { $null }
    }
}

function Repair-Prerequisite {
    param([string]$Issue)
    switch -Wildcard ($Issue) {
        'DefenderServiceNotRunning' {
            Start-Service -Name 'WinDefend' -ErrorAction Stop
            (Get-Service -Name 'WinDefend').WaitForStatus('Running', (New-TimeSpan -Seconds $ServiceTimeoutSeconds))
            Write-Log 'Started WinDefend.'
        }
        'PolicyDisablesDefender:*' {
            $name = $Issue.Split(':')[1]
            Remove-ItemProperty -Path $DefenderPolicyKey -Name $name -ErrorAction Stop
            Write-Log "Removed policy value $name. If a Group Policy sets it, fix the GPO too."
        }
        'RealTimeProtectionOff' {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            Write-Log 'Turned on real-time protection.'
        }
        'CloudProtectionOff' {
            Set-MpPreference -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -ErrorAction Stop
            Write-Log 'Turned on cloud-delivered protection (MAPS Advanced, send safe samples).'
        }
        'EngineTooOld:*' {
            $process = Start-Process -FilePath "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList '-SignatureUpdate' -PassThru -WindowStyle Hidden
            if (-not $process.WaitForExit($UpdateTimeoutMinutes * 60 * 1000)) {
                try { $process.Kill() } catch { }
                Write-Log "Engine update timed out after $UpdateTimeoutMinutes minutes."
            }
            else {
                Write-Log "MpCmdRun.exe -SignatureUpdate finished (exit code $($process.ExitCode))."
            }
        }
        'PlatformTooOld:*' {
            Write-Log "Skipped ${Issue}: install the latest Defender platform update (KB4052623) from Windows Update."
        }
        'NotOnboardedToDefenderForEndpoint' {
            Write-Log 'Skipped NotOnboardedToDefenderForEndpoint: onboard the device with an Intune EDR policy.'
        }
    }
}

try {
    Write-Log 'Starting tamper protection prerequisite remediation.'

    $thirdPartyAV = @(Get-ThirdPartyAntivirus)
    if ($thirdPartyAV.Count -gt 0) {
        $message = "Defender is not the active antivirus ($($thirdPartyAV -join ', ')). Skipping."
        Write-Log $message
        Write-Output $message
        exit 0
    }

    # Policy values first, then the service, then the settings that need the service
    $order = @('PolicyDisablesDefender:*', 'DefenderServiceNotRunning', 'RealTimeProtectionOff', 'CloudProtectionOff', 'EngineTooOld:*', 'PlatformTooOld:*', 'NotOnboardedToDefenderForEndpoint')
    $issues = @(Get-PrerequisiteIssues -State (Get-DeviceState))
    foreach ($pattern in $order) {
        foreach ($issue in @($issues | Where-Object { $_ -like $pattern })) {
            try { Repair-Prerequisite -Issue $issue }
            catch { Write-Log "Failed to fix ${issue}: $($_.Exception.Message)" }
        }
    }

    $state = Get-DeviceState
    $remaining = @(Get-PrerequisiteIssues -State $state)
    $summary = "IsTamperProtected=$($state.IsTamperProtected), Platform=$($state.PlatformVersion), Engine=$($state.EngineVersion)"

    if ($remaining.Count -gt 0) {
        $message = "Tamper protection prerequisites still missing: $($remaining -join '; '). $summary"
        Write-Log $message
        Write-Output $message
        exit 1
    }

    Write-Log "All tamper protection prerequisites are met. $summary"
    Write-Output "All tamper protection prerequisites are met. $summary"
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
