<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects Adobe packages installed on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Looks for Adobe software in three places:
      1. Installed programs (Win32/MSI) - HKLM uninstall keys, 64-bit and 32-bit.
      2. Per-user installed programs - uninstall keys of every loaded user hive (HKU).
      3. Microsoft Store (AppX/MSIX) packages - installed for any user, and provisioned in the image.

    A package counts as Adobe when its Publisher or DisplayName starts with "Adobe".
    Names listed in $ExcludeList are ignored (for example, to keep Acrobat Reader).

    Exit codes (read by Intune):
      0 = No Adobe packages found  -> device is compliant, remediation does not run.
      1 = Adobe packages found     -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeRemediation.log
#>

# Display names to keep (wildcards allowed), e.g. @('Adobe Acrobat Reader*')
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeRemediation.log"

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

function Test-IsAdobe {
    param([string]$Name, [string]$Publisher)
    return ($Name -like 'Adobe*' -or $Publisher -like 'Adobe*')
}

function Get-AdobeInstalledPrograms {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # Per-user installs: uninstall keys in every loaded user hive
    Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
        ForEach-Object {
            $paths += "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        }

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                ($_.UninstallString -or $_.QuietUninstallString) -and
                -not $_.ParentKeyName -and
                (Test-IsAdobe -Name $_.DisplayName -Publisher $_.Publisher) -and
                -not (Test-Excluded -Name $_.DisplayName)
            } |
            ForEach-Object { "Program: $($_.DisplayName) $($_.DisplayVersion)".Trim() }
    }
}

function Get-AdobeAppxPackages {
    Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -like '*Adobe*' -or $_.Publisher -like '*Adobe*') -and
            -not (Test-Excluded -Name $_.Name)
        } |
        ForEach-Object { "AppX: $($_.Name) $($_.Version)" }

    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like '*Adobe*' -and -not (Test-Excluded -Name $_.DisplayName)
        } |
        ForEach-Object { "Provisioned AppX: $($_.DisplayName) $($_.Version)" }
}

try {
    $found = @(Get-AdobeInstalledPrograms) + @(Get-AdobeAppxPackages) | Sort-Object -Unique

    if ($found.Count -gt 0) {
        Write-Log "Found $($found.Count) Adobe package(s): $($found -join '; ')"
        # Intune shows the last line of output in the admin center (max 2048 characters)
        Write-Output ("Adobe packages found ({0}): {1}" -f $found.Count, ($found -join '; '))
        exit 1
    }

    Write-Log 'No Adobe packages found.'
    Write-Output 'No Adobe packages found.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
