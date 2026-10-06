<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Reinstalls the missing corporate applications found by Detect-CorporateApps.ps1.

.DESCRIPTION
    For each missing app in $RequiredApps, by InstallType:
      Winget  -> winget install --id <InstallId> --exact --source <Source> --silent
                 --accept-package-agreements --accept-source-agreements (machine scope for the
                 winget source). winget.exe is found in the App Installer package folder because it
                 isn't on the PATH for SYSTEM.
      Command -> runs FilePath with Arguments (for example msiexec /i "\\server\share\app.msi" /qn).
      Intune  -> schedules a one-time restart of the Microsoft Intune Management Extension service
                 (2 minutes later, after this script has finished), which makes Intune check its
                 required app assignments again and reinstall missing apps.

    Exit codes 0, 3010 and 1641 count as success, and so do winget's "already installed" codes.
    Each install is stopped after $InstallTimeoutMinutes minutes. The device is never restarted.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All required apps are installed (or, for Intune apps, a re-check was requested).
      1 = One or more apps could not be installed. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CorporateAppsRemediation.log
#>

# Apps to skip by Name (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Maximum time for each install (minutes)
$InstallTimeoutMinutes = 15

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\CorporateAppsRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

# Required corporate applications - keep in sync with the detection script
#   Name        : name used in logs and $ExcludeList
#   DetectType  : Win32 (installed programs, matched on DisplayName) or Appx (Store/MSIX package name)
#   DetectName  : DisplayName or package name to look for (wildcards allowed)
#   InstallType : Winget  -> InstallId (and optional Source: winget or msstore)
#                 Command -> FilePath and Arguments (for example an MSI on a file share)
#                 Intune  -> the app is deployed by Intune; the remediation asks Intune to re-check it
$RequiredApps = @(
    @{ Name = 'Microsoft Edge';  DetectType = 'Win32'; DetectName = 'Microsoft Edge'
       InstallType = 'Winget'; InstallId = 'Microsoft.Edge'; Source = 'winget' }
    @{ Name = 'Company Portal';  DetectType = 'Appx';  DetectName = 'Microsoft.CompanyPortal'
       InstallType = 'Intune' }
    # Examples - remove the # to use:
    # @{ Name = 'Microsoft Teams'; DetectType = 'Appx'; DetectName = 'MSTeams'
    #    InstallType = 'Intune' }
    # @{ Name = 'Contoso VPN';     DetectType = 'Win32'; DetectName = 'Contoso VPN Client*'
    #    InstallType = 'Command'; FilePath = 'msiexec.exe'; Arguments = '/i "\\fileserver\apps\ContosoVPN.msi" /qn /norestart' }
)

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Get-InstalledWin32Names {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            ForEach-Object { [string]$_.DisplayName }
    }
}

function Get-InstalledAppxNames {
    $names = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $names += @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName })
    return $names
}

# Returns the required apps that are not installed
function Get-MissingApps {
    param([string[]]$Win32Names, [string[]]$AppxNames)
    foreach ($app in $RequiredApps) {
        if (Test-Excluded -Name $app.Name) { continue }
        $installed = if ($app.DetectType -eq 'Appx') { $AppxNames } else { $Win32Names }
        if (-not (@($installed | Where-Object { $_ -like $app.DetectName }).Count)) { $app }
    }
}

# winget "already installed" / "no newer version" results count as success
$SuccessExitCodes = @(0, 3010, 1641, -1978335189, -1978335135)

function Get-WingetPath {
    $candidates = @(Resolve-Path -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object -Property Path -Descending)
    if ($candidates.Count -gt 0) { return $candidates[0].Path }
    return $null
}

# Builds the winget arguments for an app
function Get-WingetArguments {
    param($App)
    $source = if ($App.Source) { $App.Source } else { 'winget' }
    $arguments = "install --id `"$($App.InstallId)`" --exact --source $source --silent --accept-package-agreements --accept-source-agreements"
    if ($source -eq 'winget') { $arguments += ' --scope machine' }
    return $arguments
}

function Invoke-Install {
    param([string]$FilePath, [string]$Arguments, [string]$Name)
    Write-Log "Installing '$Name': `"$FilePath`" $Arguments"
    $startParams = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Arguments) { $startParams.ArgumentList = $Arguments }
    $process = Start-Process @startParams
    if (-not $process.WaitForExit($InstallTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { }
        Write-Log "Install of '$Name' timed out after $InstallTimeoutMinutes minutes."
        return $false
    }
    if ($process.ExitCode -in $SuccessExitCodes) {
        Write-Log "Installed '$Name' (exit code $($process.ExitCode))."
        return $true
    }
    Write-Log "Install of '$Name' failed (exit code $($process.ExitCode))."
    return $false
}

$script:IntuneRecheckRequested = $false

# Restarts the Intune Management Extension 2 minutes from now through a one-time scheduled task.
# It can't be restarted directly: it is the service running this script.
function Request-IntuneRecheck {
    if ($script:IntuneRecheckRequested) { return $true }
    try {
        $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -Command "Restart-Service -Name IntuneManagementExtension -Force"'
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
        $trigger.EndBoundary = (Get-Date).AddMinutes(30).ToString('s')
        $settings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 1) -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'IntuneRemediation-RecheckCorporateApps' -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log 'Scheduled a restart of the Intune Management Extension in 2 minutes so Intune re-checks required apps.'
        $script:IntuneRecheckRequested = $true
        return $true
    }
    catch {
        Write-Log "Could not schedule the Intune Management Extension restart: $($_.Exception.Message)"
        return $false
    }
}

function Install-App {
    param($App)
    switch ($App.InstallType) {
        'Winget' {
            $winget = Get-WingetPath
            if (-not $winget) { Write-Log "Skipped '$($App.Name)': winget (App Installer) is not installed."; return $false }
            return (Invoke-Install -FilePath $winget -Arguments (Get-WingetArguments -App $App) -Name $App.Name)
        }
        'Command' {
            return (Invoke-Install -FilePath $App.FilePath -Arguments $App.Arguments -Name $App.Name)
        }
        'Intune' {
            return (Request-IntuneRecheck)
        }
        default {
            Write-Log "Skipped '$($App.Name)': unknown InstallType '$($App.InstallType)'."
            return $false
        }
    }
}

try {
    Write-Log 'Starting corporate app remediation.'
    $missing = @(Get-MissingApps -Win32Names @(Get-InstalledWin32Names) -AppxNames @(Get-InstalledAppxNames))
    $failed = @()

    # Win32 / winget installs first; the Intune re-check last
    foreach ($app in @($missing | Sort-Object -Property @{ Expression = { $_.InstallType -eq 'Intune' } })) {
        if (-not (Install-App -App $app)) { $failed += $app.Name }
    }

    # Intune apps are installed later by the Intune Management Extension, so only check the others now
    $stillMissing = @(Get-MissingApps -Win32Names @(Get-InstalledWin32Names) -AppxNames @(Get-InstalledAppxNames) |
        Where-Object { $_.InstallType -ne 'Intune' } | ForEach-Object { $_.Name })
    $notInstalled = @(@($failed) + @($stillMissing) | Sort-Object -Unique)

    if ($notInstalled.Count -gt 0) {
        $message = "Could not install: $($notInstalled -join ', '). See the log."
        Write-Log $message
        Write-Output $message
        exit 1
    }

    $message = "Reinstalled or requested $($missing.Count) missing app(s): $((@($missing | ForEach-Object { $_.Name })) -join ', ')."
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
