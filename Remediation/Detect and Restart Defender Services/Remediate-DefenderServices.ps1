<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Starts the Microsoft Defender services found stopped by Detect-DefenderServices.ps1.

.DESCRIPTION
    Uses the same service list and rules as the detection script. For each required
    service that is not running:
      - Stopped, start type Automatic or Manual -> Start-Service, then wait up to
        $ServiceTimeoutSeconds for it to reach Running.
      - Stuck in StartPending / StopPending     -> wait up to $ServiceTimeoutSeconds, then start it.
      - Disabled                                -> Skipped and logged. Defender services are protected
        (and Tamper Protection blocks changes), so a script can't re-enable them. A disabled
        Defender service usually means a policy or another security product turned it off.

    Running Defender services are never stopped or restarted: Windows does not allow
    scripts to stop them.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All required Defender services are running.
      1 = One or more required services are still not running.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderServicesRemediation.log
    No restart is needed.
#>

# Service names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Maximum time to wait for one service to start (seconds)
$ServiceTimeoutSeconds = 120

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderServicesRemediation.log"

# Same list as the detection script - keep in sync
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

function Start-DefenderService {
    param($Failed)

    $label = "$($Failed.Name) ($($Failed.DisplayName))"

    if ($Failed.StartType -eq 'Disabled') {
        Write-Log "Skipped $label`: service is Disabled. Check Intune/Group Policy antivirus settings and other security products."
        return $false
    }

    $timeout = New-TimeSpan -Seconds $ServiceTimeoutSeconds
    try {
        $service = Get-Service -Name $Failed.Name -ErrorAction Stop

        # Let a service that is already starting or stopping settle first
        if ($service.Status -eq 'StartPending') {
            $service.WaitForStatus('Running', $timeout)
        }
        elseif ($service.Status -eq 'StopPending') {
            $service.WaitForStatus('Stopped', $timeout)
        }

        $service.Refresh()
        if ($service.Status -ne 'Running') {
            Write-Log "Starting $label (was $($service.Status))."
            Start-Service -Name $Failed.Name -ErrorAction Stop
            $service.WaitForStatus('Running', $timeout)
        }

        $service.Refresh()
        Write-Log "$label is $($service.Status)."
        return ($service.Status -eq 'Running')
    }
    catch {
        # WaitForStatus throws System.ServiceProcess.TimeoutException when the timeout passes
        Write-Log "Failed to start $label`: $($_.Exception.Message)"
        return $false
    }
}

try {
    Write-Log 'Starting Defender service remediation.'
    $notFixed = @()
    $started = 0

    foreach ($failed in @(Get-FailedDefenderServices)) {
        if (Start-DefenderService -Failed $failed) {
            $started++
        }
        else {
            $notFixed += "$($failed.Name): $($failed.Status), $($failed.StartType)"
        }
    }

    if ($notFixed.Count -gt 0) {
        $summary = "Started $started Defender service(s). Still not running: $($notFixed -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Log $summary
        Write-Output $summary
        exit 1
    }

    Write-Log "Started $started Defender service(s). All required Defender services are running."
    Write-Output "Started $started Defender service(s). All required Defender services are running."
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
