<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects devices that don't meet the prerequisites for Microsoft Defender tamper protection
    on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Tamper protection itself can only be turned on centrally (Intune antivirus policy or the
    Microsoft Defender portal), not by a script. This remediation makes sure each device is
    ready for it. Checks (names in brackets are reported in the output):
      - Microsoft Defender Antivirus service is running              (DefenderServiceNotRunning)
      - No policy turns Defender off (DisableAntiSpyware/AntiVirus)  (PolicyDisablesDefender:<value>)
      - Real-time protection is on                                   (RealTimeProtectionOff)
      - Cloud-delivered protection (MAPS) is on                      (CloudProtectionOff)
      - Defender platform version 4.18.2010.7 or later               (PlatformTooOld:<version>)
      - Defender engine version 1.1.17600.5 or later                 (EngineTooOld:<version>)
      - Device is onboarded to Microsoft Defender for Endpoint       (NotOnboardedToDefenderForEndpoint)
        (required to manage tamper protection from Intune or the Defender portal)

    Devices where another antivirus product is active are reported as compliant.
    Check names matching $ExcludeList are not checked.

    Exit codes (read by Intune):
      0 = All prerequisites are met.
      1 = One or more prerequisites are missing -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TamperProtectionRemediation.log
#>

# Checks to skip by name (wildcards allowed), e.g. @('NotOnboardedToDefenderForEndpoint')
$ExcludeList = @()

$MinimumPlatformVersion = [version]'4.18.2010.7'
$MinimumEngineVersion = [version]'1.1.17600.5'
$DefenderPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\TamperProtectionRemediation.log"

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

function Test-VersionBelow {
    param([string]$Version, [version]$Minimum)
    $parsed = $null
    if (-not [version]::TryParse($Version, [ref]$parsed)) { return $true }
    return ($parsed -lt $Minimum)
}

# Builds the list of missing prerequisites from the collected device state
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

try {
    $thirdPartyAV = @(Get-ThirdPartyAntivirus)
    if ($thirdPartyAV.Count -gt 0) {
        Write-Log "Another antivirus product is active ($($thirdPartyAV -join ', ')). Skipping."
        Write-Output "Defender is not the active antivirus ($($thirdPartyAV -join ', ')). Skipping."
        exit 0
    }

    $state = Get-DeviceState
    $issues = @(Get-PrerequisiteIssues -State $state)
    $summary = "IsTamperProtected=$($state.IsTamperProtected), Platform=$($state.PlatformVersion), Engine=$($state.EngineVersion)"

    if ($issues.Count -gt 0) {
        Write-Log "Missing prerequisites: $($issues -join '; '). $summary"
        Write-Output "Tamper protection prerequisites missing: $($issues -join '; '). $summary"
        exit 1
    }

    Write-Log "All tamper protection prerequisites are met. $summary"
    Write-Output "All tamper protection prerequisites are met. $summary"
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
