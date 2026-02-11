WSL Docker rootfs (Ubuntu 24.04 'noble')

Quick install (run an elevated PowerShell prompt — Run as Administrator):

Copy and paste this single line into an elevated PowerShell window to download and run the installer:

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/install-wsl.ps1 | iex
```

Notes:
- The installer imports the prebuilt rootfs tarball and then enumerates candidate GPT disks that contain a single Linux partition (ext4). It will print suggested `wsl --mount` commands for manual execution.
- Do not run the one-liner unless you trust the source; verify the script/release checksums in the repo before running in production.

Uninstall:

To remove the imported distro and stored files, run the uninstall script from an elevated PowerShell prompt:

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/uninstall-wsl.ps1 | iex
```

This script unregisters the distro, attempts to unmount the VHDX, and deletes the stored files under your Windows user folder.
# wsl-docker
A basic WSL2 configuration for running container services.
