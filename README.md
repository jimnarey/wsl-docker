# wsl-docker

A pre-configured Ubuntu Noble distribution for Windows Subsystem for Linux 2 (WSL 2), designed to enable running Docker containers with as close-to a native Ubuntu experience as possible.

This has been tested only on Windows 11. It may or may not work on Windows 10.

## Installing WSL 2

WSL 2 is not installed on Windows 11 by default. The steps for installing it are pretty straightfoward but this repository includes a script to do so in a single step. Run the following in an elevated Powershell terminal (i.e. right click Powershell and select 'Run as Administrator):

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/install-wsl.ps1 | iex
```

## Installing the distribution

Once WSL 2 is installed (you may need to reboot) run the following, also in an elevated Powershell terminal:

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/install-wsl-distro.ps1 | iex
```

The script does the following:

- Downloads the prebuilt Ubuntu rootfs tarball from the latest release.
- Downloads a bootstrap provisioning script to `%USERPROFILE%\container-host-noble\bootstrap.sh`
- Imports the rootfs as a new WSL 2 distribution with the name `container-host-noble`
- Downloads a VHDX image file to act as the `/home` directory for the distribution to `%USERPROFILE%\container-host-noble\home.vhdx`
- Attaches the VHDX to WSL and triggers mounting inside the distro.
- Enumerates GPT disks with a single Linux partition and suggests manual mount commands if found.
- Deletes any temporary files used during installation, including the pre-built distribution, keeping only the VHDX file and the `bootstrap.sh` script.

## One-time bootstrap

To finalise setup of the distribution the `bootstrap.sh` script downloaded by the distribution installer must be run once (it can be subsequently run and will have no effect):

- Ensures the main user is in the docker group for container management.
- Configures NVIDIA container toolkit runtimes if available (for GPU support).
- Does not use systemd; instead, sets up a supervisor-based service starter.
- Can optionally clone a repository if environment variables are set.
- After completion, services (containerd, dockerd, sshd) will start automatically when an interactive non-root shell is opened, or can be started manually with `/usr/local/bin/start-services`.

```powershell
wsl -d container-host-noble -- bash /mnt/c/Users/%USERNAME%/container-host-noble/bootstrap.sh
```

To run the script and clone a specified git repository:

```powershell
wsl -d container-host-noble -- env REPO_URL=https://github.com/your/repo.git REPO_DEST=/home/ubuntu/destination bash /mnt/c/Users/%USERNAME%/container-host-noble/bootstrap.sh
```

## Uninstalling the distribution

To remove the imported distro and stored files, run the uninstall script from an elevated PowerShell prompt:

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/uninstall-distro.ps1 | iex
```

This script unregisters the distro, attempts to unmount the VHDX, and deletes the stored files under your Windows user folder.

The repo does not contain a script for uninstalling/deactivating WSL itself.

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
