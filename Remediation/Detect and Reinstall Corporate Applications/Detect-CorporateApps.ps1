<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects missing corporate applications on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Checks that every app in $RequiredApps is installed:
      - Win32 apps: matched on DisplayName in the installed programs list (HKLM uninstall keys,
        64-bit and 32-bit).
      - Appx apps : matched on package name, installed for any user or provisioned in the image.

    Apps whose Name matches $ExcludeList are not checked.

    Exit codes (read by Intune):
      0 = All required apps are installed.
      1 = One or more required apps are missing -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CorporateAppsRemediation.log
#>

# Apps to skip by Name (wildcards allowed), e.g. @('Company Portal')
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\CorporateAppsRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

# Required corporate applications
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

try {
    $missing = @(Get-MissingApps -Win32Names @(Get-InstalledWin32Names) -AppxNames @(Get-InstalledAppxNames))

    if ($missing.Count -gt 0) {
        $names = @($missing | ForEach-Object { $_.Name })
        Write-Log "Missing $($missing.Count) required app(s): $($names -join ', ')"
        Write-Output "Missing corporate apps ($($missing.Count)): $($names -join ', ')"
        exit 1
    }

    Write-Log 'All required apps are installed.'
    Write-Output 'All required corporate apps are installed.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
