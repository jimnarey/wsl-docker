# wsl-docker

A pre-configured Ubuntu Noble distribution for Windows Subsystem for Linux 2 (WSL 2), designed to enable running Docker containers with as close-to a native Ubuntu experience as possible.

It requires Windows 11 and at least 22H2 (released 2022) to be accessible via ssh from a different machine.

## Installing WSL 2

WSL 2 is not installed on Windows 11 by default. The steps for installing it are pretty straightfoward but this repository includes a script to do so in a single step. Run the following in an elevated Powershell terminal (i.e. right click Powershell and select 'Run as Administrator):

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/install-wsl.ps1 | iex
```

Amongst other actions this script sets the default WSL version to 2.

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
wsl -d container-host-noble -- sudo bash /mnt/c/Users/$env:USERNAME/container-host-noble/bootstrap.sh
```
The default password for the ubuntu user is `ubuntu`.

To run the script and clone a specified git repository:

```powershell
wsl -d container-host-noble -- env REPO_URL=https://github.com/your/repo.git REPO_DEST=/home/ubuntu/destination sudo bash /mnt/c/Users/$env:USERNAME/container-host-noble/bootstrap.sh
```

### Accessing the distro via ssh

Run the following commands prior to running the distro or later, while it is not running.

```powershell
wsl --port add --protocol tcp --hostport 2222 --guestport 22
New-NetFirewallRule -DisplayName "WSL SSH" -Direction Inbound -LocalPort 2222 -Protocol TCP -Action Allow
```

## Running the distro

After importing the rootfs (via the provided installer or `wsl --import`), you can start and interact with the distro like any WSL distribution.

- Start an interactive shell in the distro:

```powershell
wsl -d container-host-noble
```

- Run a single command inside the distro:

```powershell
wsl -d container-host-noble -- ls -la
```

### Other useful commands

- List all installed distros: `wsl --list --verbose`
- List running distros: `wsl --list --running`


## Uninstalling the distribution

To remove the imported distro and stored files, run the uninstall script from an elevated PowerShell prompt:

```powershell
iwr -useb https://raw.githubusercontent.com/jimnarey/wsl-docker/main/scripts/uninstall-distro.ps1 | iex
```

This script unregisters the distro, attempts to unmount the VHDX, and deletes the stored files under your Windows user folder.

The repo does not contain a script for uninstalling/deactivating WSL itself.