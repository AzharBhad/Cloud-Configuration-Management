<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects Microsoft Defender services that should be running but are stopped or disabled
    on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Checks these services (names in brackets):
      Microsoft Defender Antivirus Service        (WinDefend)
      Microsoft Defender Antivirus Network Inspection Service (WdNisSvc)
      Microsoft Defender Core Service             (MDCoreSvc)  - only on newer Defender platform versions
      Microsoft Defender for Endpoint             (Sense)      - only on devices onboarded to Defender for Endpoint
      Windows Security Service                    (SecurityHealthService)
      Security Center                             (wscsvc)
      Windows Defender Firewall                   (mpssvc)

    A service is reported when it is installed, required on this device, and not Running.
    Services that are stopped on purpose are not reported:
      - WinDefend, WdNisSvc and MDCoreSvc when another antivirus product is active.
      - Sense when the device is not onboarded to Defender for Endpoint.
      - Services listed in $ExcludeList.

    Exit codes (read by Intune):
      0 = All required Defender services are running -> remediation does not run.
      1 = One or more required services are stopped or disabled -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderServicesRemediation.log
#>

# Service names to skip (wildcards allowed), e.g. @('mpssvc') if another firewall is used
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderServicesRemediation.log"

# Condition: Always = always required; DefenderAV = required when Defender is the active antivirus;
#            Onboarded = required when the device is onboarded to Defender for Endpoint
$DefenderServices = @(
    @{ Name = 'WinDefend';             Condition = 'DefenderAV' }
    @{ Name = 'WdNisSvc';              Condition = 'DefenderAV' }
    @{ Name = 'MDCoreSvc';             Condition = 'DefenderAV' }
    @{ Name = 'Sense';                 Condition = 'Onboarded' }
    @{ Name = 'SecurityHealthService'; Condition = 'Always' }
    @{ Name = 'wscsvc';                Condition = 'Always' }
    @{ Name = 'mpssvc';                Condition = 'Always' }
)

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

# True when the Security Center productState says the antivirus product is turned on.
# Byte 2 of productState: 0x10 / 0x11 = on, 0x00 / 0x01 = off.
function Test-ProductEnabled {
    param([int]$ProductState)
    return ((($ProductState -shr 8) -band 0xFF) -in 0x10, 0x11)
}

# Names of active antivirus products other than Microsoft Defender
function Get-ThirdPartyAntivirus {
    $products = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction SilentlyContinue
    foreach ($product in $products) {
        if ($product.displayName -notlike '*Defender*' -and (Test-ProductEnabled -ProductState $product.productState)) {
            $product.displayName
        }
    }
}

function Test-DefenderForEndpointOnboarded {
    $status = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' `
        -Name 'OnboardingState' -ErrorAction SilentlyContinue
    return ($status -and $status.OnboardingState -eq 1)
}

function Test-ServiceRequired {
    param([string]$Condition, [bool]$DefenderIsActiveAV, [bool]$Onboarded)
    switch ($Condition) {
        'DefenderAV' { return $DefenderIsActiveAV }
        'Onboarded'  { return $Onboarded }
        default      { return $true }
    }
}

function Get-FailedDefenderServices {
    $thirdPartyAV = @(Get-ThirdPartyAntivirus)
    $defenderIsActiveAV = ($thirdPartyAV.Count -eq 0)
    $onboarded = Test-DefenderForEndpointOnboarded

    if (-not $defenderIsActiveAV) {
        Write-Log "Another antivirus product is active ($($thirdPartyAV -join ', ')). Skipping Defender Antivirus services."
    }

    foreach ($entry in $DefenderServices) {
        if (Test-Excluded -Name $entry.Name) { continue }
        if (-not (Test-ServiceRequired -Condition $entry.Condition -DefenderIsActiveAV $defenderIsActiveAV -Onboarded $onboarded)) { continue }

        $service = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $service) { continue }

        if ($service.StartType -eq 'Disabled' -or $service.Status -ne 'Running') {
            [pscustomobject]@{
                Name        = $service.Name
                DisplayName = $service.DisplayName
                Status      = [string]$service.Status
                StartType   = [string]$service.StartType
            }
        }
    }
}

try {
    $failed = @(Get-FailedDefenderServices)

    if ($failed.Count -gt 0) {
        $labels = @($failed | ForEach-Object { "$($_.Name) ($($_.DisplayName)): $($_.Status), $($_.StartType)" })
        Write-Log "Found $($failed.Count) Defender service(s) not running: $($labels -join '; ')"
        # Intune shows the last line of output in the admin center (max 2048 characters)
        $summary = "Defender services not running ({0}): {1}" -f $failed.Count, ($labels -join '; ')
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Log 'All required Defender services are running.'
    Write-Output 'All required Defender services are running.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
