<#
.SYNOPSIS
  Unregister and remove a WSL distribution created by install-wsl.ps1

DESCRIPTION
  This script terminates and unregisters the given WSL distribution, attempts to
  unmount any attached VHDX created by the installer, and deletes the stored
  files (VHDX, bootstrap script) and the imported distro files.

USAGE
  Run in an elevated PowerShell prompt. Example:
    .\uninstall-wsl.ps1 -DistroName ubuntu-noble

  Use `-Force` to skip confirmation.
#>

param(
    [string]$DistroName = 'container-host-noble',
    [switch]$Force
)

function Is-Administrator {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Administrator)) {
    Write-Error "This script must be run as Administrator. Relaunch in an elevated PowerShell."; return
}

$storeDir = Join-Path $env:USERPROFILE ("$DistroName")
$installDir = Join-Path $env:LOCALAPPDATA ("wsl\$DistroName")
$vhdPath = Join-Path $storeDir 'home.vhdx'

Write-Host "About to remove WSL distro: $DistroName"
Write-Host "Install directory: $installDir"
Write-Host "Persistent store directory: $storeDir"

# Proceed non-interactively (no prompt)

try {
    Write-Host "Terminating distro if running..."
    & wsl.exe --terminate $DistroName 2>$null
} catch {
    Write-Warning "Failed to terminate distro (it may not be running): $_"
}

if (Test-Path $vhdPath) {
    try {
        Write-Host "Attempting to unmount VHDX via wsl --unmount $vhdPath"
        & wsl.exe --unmount $vhdPath 2>$null
    } catch {
        Write-Warning "wsl --unmount failed or VHD not attached: $_"
    }
}

try {
    Write-Host "Unregistering distro: $DistroName"
    & wsl.exe --unregister $DistroName
} catch {
    Write-Warning "Failed to unregister distro: $_"
}

if (Test-Path $storeDir) {
    try {
        Write-Host "Removing store directory: $storeDir"
        Remove-Item -Path $storeDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "Failed to remove store directory: $_"
    }
} else { Write-Host "Store directory not found: $storeDir" }

if (Test-Path $installDir) {
    try {
        Write-Host "Removing install directory: $installDir"
        Remove-Item -Path $installDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "Failed to remove install directory: $_"
    }
} else { Write-Host "Install directory not found: $installDir" }

Write-Host "Uninstall completed. If any resources remain attached, consider running 'wsl --shutdown' and retrying";
return
