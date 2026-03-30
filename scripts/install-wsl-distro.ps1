<#
.SYNOPSIS
    Download a prebuilt rootfs tarball, import into WSL2 with `wsl --import`,
    and list GPT disks that contain exactly one partition of the Linux GPT type.

USAGE
    Run this script in an elevated PowerShell prompt after prerequisites are installed.
    Example:
        .\install-wsl-distro.ps1
#>


$ReleaseApiUrl = 'https://api.github.com/repos/jimnarey/wsl-docker/releases/tags/ubuntu-noble-amd64'
$DistroName = 'container-host-noble'
$AssetFileName = 'ubuntu-noble-amd64.tar.gz'
$storeDir = Join-Path $env:USERPROFILE 'container-host-noble'
$hashFile = Join-Path $storeDir 'asset-hashes.json'

function Get-ReleaseAssets {
    param([string]$ApiUrl)
    $headers = @{ 'User-Agent' = 'wsl-distro-installer' }
    $json = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -UseBasicParsing
    $assets = @{}
    foreach ($a in $json.assets) {
        $assets[$a.name] = @{ url = $a.browser_download_url; sha256 = $a.sha256; size = $a.size }
    }
    return $assets
}

function Get-RemoteHashes {
    param([hashtable]$assets)
    $hashes = @{}
    foreach ($k in $assets.Keys) {
        $sha = $assets[$k]['sha256']
        if ($sha) { $hashes[$k] = $sha }
    }
    return $hashes
}

function Load-LocalHashes {
    param([string]$Path)
    if (Test-Path $Path) {
        try { return Get-Content $Path | ConvertFrom-Json } catch { return @{} }
    } else {
        return @{}
    }
}

function Save-LocalHashes {
    param([string]$Path, $Hashes)
    $Hashes | ConvertTo-Json | Set-Content $Path
}

function Get-FileHashHex {
    param([string]$Path)
    if (Test-Path $Path) {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
    } else {
        return ''
    }
}

function Download-If-Changed {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Dest,
        [string]$ExpectedHash,
        [hashtable]$LocalHashes
    )
    $currentHash = Get-FileHashHex $Dest
    $savedHash = if ($LocalHashes.ContainsKey($Name)) { $LocalHashes[$Name] } else { '' }
    if ($currentHash -and $currentHash -eq $ExpectedHash -and $savedHash -eq $ExpectedHash) {
        Write-Host "$Name is up to date. Skipping download."
        return $false
    }
    Write-Host "Downloading $Name ..."
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
    $newHash = Get-FileHashHex $Dest
    if ($newHash -ne $ExpectedHash) {
        Abort "$Name hash mismatch after download."
    }
    $LocalHashes[$Name] = $ExpectedHash
    return $true
}

# Main logic
if (-not (Test-Path $storeDir)) { New-Item -Path $storeDir -ItemType Directory -Force | Out-Null }
$assets = Get-ReleaseAssets $ReleaseApiUrl
$remoteHashes = Get-RemoteHashes $assets
$localHashes = Load-LocalHashes $hashFile

# Download and verify each asset
$tarName = 'ubuntu-noble-amd64.tar.gz'
$vhdxName = 'home.vhdx'
$bootstrapName = 'bootstrap.sh'
$tarPath = Join-Path $storeDir $tarName
$vhdxPath = Join-Path $storeDir $vhdxName
$bootstrapPath = Join-Path $storeDir $bootstrapName

Download-If-Changed -Name $tarName -Url $assets[$tarName].url -Dest $tarPath -ExpectedHash $remoteHashes[$tarName] -LocalHashes $localHashes | Out-Null
Download-If-Changed -Name $vhdxName -Url $assets[$vhdxName].url -Dest $vhdxPath -ExpectedHash $remoteHashes[$vhdxName] -LocalHashes $localHashes | Out-Null
Download-If-Changed -Name $bootstrapName -Url $assets[$bootstrapName].url -Dest $bootstrapPath -ExpectedHash $remoteHashes[$bootstrapName] -LocalHashes $localHashes | Out-Null

Save-LocalHashes -Path $hashFile -Hashes $localHashes

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

try {
    & wsl.exe --set-default-version 2 2>$null
} catch {
    Write-Warning "Unable to set default WSL version to 2 automatically. You may need to update Windows or enable features manually."
}

$tmp = Join-Path $env:TEMP ('wsl_install_' + (Get-Date -Format yyyyMMddHHmmss))
New-Item -Path $tmp -ItemType Directory -Force | Out-Null
$tarPath = Join-Path $tmp $AssetFileName

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutPath
    )

    Write-Host "Downloading: $Url -> $OutPath"
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            Write-Host "Using curl.exe for download (resume + retries)."
            $curl = (Get-Command curl.exe).Source
            $curlArgs = @('-L', '--retry', '5', '--retry-delay', '2', '--retry-max-time', '120', '--progress-bar', '-C', '-', '--fail', '-o', "$OutPath", "$Url")
            & $curl @curlArgs
        }
        elseif (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Write-Host "Using Start-BitsTransfer for download."
            Start-BitsTransfer -Source $Url -Destination $OutPath -Priority Normal -RetryInterval 60 -RetryTimeout 3600
        }
        else {
            Write-Host "Falling back to Invoke-WebRequest."
            Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -ErrorAction Stop
        }
    } catch {
        Abort "Download failed: $_" 3
    }
    Write-Host "Downloaded: $OutPath"
}


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

# Attach the preformatted home VHDX so that /etc/fstab inside the distro can mount it
if (Test-Path $vhdxPath) {
    Write-Host "Attaching VHDX to WSL: $vhdxPath"
    try {
        & wsl.exe --mount --vhd $vhdxPath
        Write-Host "VHDX attached. Triggering mount inside distro to honor /etc/fstab"
        & wsl.exe -d $DistroName -- bash -lc "sleep 1; mount -a || true"
    } catch {
        Write-Warning "Failed to attach or mount VHDX inside WSL: $_"
    }
} else {
    Write-Warning "Expected VHDX not found at $vhdxPath; skipping attach"
}

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

Write-Host "Cleaning up temporary files..."
try {
    if (Test-Path $tarPath) { Remove-Item -Path $tarPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmp) { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
} catch {
    Write-Warning "Failed to remove some temporary files: $_"
}

Write-Host "Temporary files removed. Persistent files kept in: $storeDir"

return
