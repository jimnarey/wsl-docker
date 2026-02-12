````markdown
# wsl-docker

A basic WSL2 configuration for running container services.

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


## How to run the distro

After importing the rootfs (via the provided installer or `wsl --import`), you can start and interact with the distro like any WSL distribution.

- Start an interactive shell in the distro:

```bash
wsl -d <DistroName>
# example: wsl -d wsl-docker
```

- Run a single command inside the distro:

```bash
wsl -d <DistroName> -- /bin/bash -lc "echo hello from distro"
```

- If you used the Windows installer script, you can also use the included helper to import/uninstall the distro:

```powershell
# Import (example - use the installer for a release tarball)
./scripts/install-wsl.ps1 -DistroName wsl-docker -RootfsPath .\path\to\rootfs.tar

# Uninstall
./scripts/uninstall-wsl.ps1 -DistroName wsl-docker
```

Notes:
- Replace `<DistroName>` with the name you used when importing the distro.
- On Windows, run the PowerShell commands from an elevated PowerShell prompt when required.

````


