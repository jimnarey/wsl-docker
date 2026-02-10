<#
.SYNOPSIS
    Download a prebuilt rootfs tarball (hardcoded), import into WSL2 with `wsl --import`,
    and list GPT disks that contain exactly one partition of the Linux GPT type.

USAGE
    - Recommended: run the one-line installer from the README in an elevated PowerShell
        (Run as Administrator). Example:
            iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/install-wsl.ps1 | iex

NOTES
    - The download URL is hardcoded in this script and points to the repository release
        asset `ubuntu-noble-amd64.tar.gz`.
    - This script requires Administrator privileges (it will abort if not elevated).
    - The script will NOT offline or modify disks; it only enumerates candidate GPT disks
        and prints suggested `wsl --mount` commands for manual execution.
    - The script attempts to enable WSL features and run `wsl --install` if `wsl.exe`
        is missing; in that case it may exit and require a reboot before re-running.
#>

$DownloadUrl = 'https://github.com/jimnarey/wsl-docker/releases/download/ubuntu-noble-amd64/ubuntu-noble-amd64.tar.gz'
$DistroName = 'ubuntu-noble'
$AssetFileName = 'ubuntu-noble-amd64.tar.gz'

function Abort([string]$msg) {
    Write-Error $msg
    throw $msg
}

## Check we have admin privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Abort 'This script must be run as Administrator. Relaunch in an elevated PowerShell.' 2
}

$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCmd) {
    Write-Host "wsl.exe not found — attempting to enable WSL features and invoke 'wsl --install'"
    try {
        Write-Host "Enabling required Windows features (may require reboot)..."
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    } catch {
        Write-Warning "Failed to enable features via DISM: $_"
    }

    try {
        & wsl.exe --install
        Write-Host "Invoked 'wsl --install'. A reboot may be required; re-run this script after reboot if necessary."
        return
    } catch {
        Abort "wsl --install failed or is not available on this system: $_" 2
    }
}

try {
    & wsl.exe --set-default-version 2 2>$null
} catch {
    Write-Warning "Unable to set default WSL version to 2 automatically. You may need to update Windows or enable features manually."
}

$tmp = Join-Path $env:TEMP ('wsl_install_' + (Get-Date -Format yyyyMMddHHmmss))
New-Item -Path $tmp -ItemType Directory -Force | Out-Null
$tarPath = Join-Path $tmp $AssetFileName

Write-Host "Downloading rootfs from: $DownloadUrl"
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $tarPath -UseBasicParsing -ErrorAction Stop
} catch {
    Abort "Download failed: $_" 3
}

Write-Host "Downloaded to $tarPath"

$installDir = Join-Path $env:LOCALAPPDATA ("wsl\$DistroName")
Write-Host "Importing distro as '$DistroName' into: $installDir"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

try {
    & wsl.exe --import $DistroName $installDir $tarPath --version 2
} catch {
    $err = $_
    $errMsg = if ($err.Exception) { $err.Exception.Message } else { $err.ToString() }

    if ($errMsg -match 'HCS_E_SERVICE_NOT_AVAILABLE' -or $errMsg -match 'required feature is not installed' -or $errMsg -match 'Wsl/Service/RegisterDistro/CreateVm') {
        Write-Error "wsl --import failed because the virtualization host service appears unavailable. This commonly happens when VirtualMachinePlatform or Hyper-V was enabled but the machine hasn't been rebooted."
        Write-Host "Recommended action: reboot the machine to finish installing VirtualMachinePlatform/WSL components, then re-run this script."

        $resp = Read-Host "Would you like to reboot now? (Y/N)"
        if ($resp -match '^[Yy]') {
            Write-Host "Rebooting now..."
            shutdown /r /t 5
        }

        Abort "wsl --import failed: $errMsg"
    }

    Abort "wsl --import failed: $errMsg"
}

Write-Host "Import complete. Now enumerating GPT disks with a single Linux partition..."

$linuxGpt = '0fc63daf-8483-4772-8e79-3d69d8477de4'

$candidates = @()
Get-Disk | Where-Object PartitionStyle -eq 'GPT' | ForEach-Object {
    $disk = $_
    $parts = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    if (-not $parts) { return }
    if ($parts.Count -ne 1) { return }
    $p = $parts[0]
    if (-not $p.GptType) { return }
    if ($p.GptType.ToString().ToLower() -eq $linuxGpt) {
        $devicePath = "\\.\PHYSICALDRIVE$($disk.Number)"
        $mountCmd = "wsl --mount $devicePath --partition $($p.PartitionNumber) --type ext4"
        $candidates += [PSCustomObject]@{
            DiskNumber = $disk.Number
            DevicePath = $devicePath
            PartitionNumber = $p.PartitionNumber
            PartitionStyle = $disk.PartitionStyle
            GptType = $p.GptType
            SuggestedMountCommand = $mountCmd
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No GPT disks with exactly one Linux partition (GUID $linuxGpt) were found."
} else {
    Write-Host "Candidate disks:"
    $candidates | Format-Table -AutoSize
    Write-Host "\nSuggested manual mount commands (run as Administrator):"
    foreach ($c in $candidates) { Write-Host $c.SuggestedMountCommand }
}

Write-Host "Temporary files kept at: $tmp (remove when no longer needed)"

return
