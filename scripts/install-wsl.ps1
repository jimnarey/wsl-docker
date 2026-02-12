<#
.SYNOPSIS
    Install or enable Windows components required by WSL and attempt to run `wsl --install`.

USAGE
    Run this script in an elevated PowerShell prompt (Run as Administrator).
    Example:
        .\install-wsl-prereqs.ps1
#>

function Abort([string]$msg) {
    Write-Error $msg
    throw $msg
}

function Is-Administrator {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Administrator)) {
    Abort 'This script must be run as Administrator. Relaunch in an elevated PowerShell.'
}

Write-Host "Ensuring WSL and Virtual Machine Platform features are enabled (may require reboot)..."
try {
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
} catch {
    Write-Warning "Failed to enable features via DISM: $_"
}

# Attempt to invoke the modern WSL installer if available
try {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        Write-Host "wsl.exe found. Setting default WSL version to 2."
        try { & wsl.exe --set-default-version 2 2>$null } catch { Write-Warning "Failed to set default WSL version: $_" }
        Write-Host "Prereqs appear satisfied. You can now run the distro installer script."
        return
    } else {
        Write-Host "wsl.exe not found — attempting to run 'wsl --install' to install WSL components."
        & wsl.exe --install
        Write-Host "Invoked 'wsl --install'. A reboot may be required; re-run the distro installer after reboot if necessary."
        return
    }
} catch {
    Write-Warning "Attempt to install or configure WSL failed: $_"
    Abort "Prerequisite installation failed: $_"
}
return
