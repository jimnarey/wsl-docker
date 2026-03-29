#!/bin/bash
set -euo pipefail

# Minimal chroot provisioner to install Docker CE and NVIDIA container toolkit
# Run inside a chroot (root is the target rootfs)

export DEBIAN_FRONTEND=noninteractive

echo "Preparing apt sources and cache permissions..."
# Ensure apt cache dirs exist and are writable by _apt to avoid sandbox warnings
mkdir -p /var/cache/apt/archives/partial
if id -u _apt >/dev/null 2>&1; then
  chown -R _apt:root /var/cache/apt/archives || true
  chmod 0755 /var/cache/apt/archives || true
  chmod 0700 /var/cache/apt/archives/partial || true
fi

# Enable 'universe' component so packages like 'supervisor' are available
if [ -f /etc/apt/sources.list ]; then
  # Append 'universe' to Ubuntu archive lines if not present
  sed -n '1,200p' /etc/apt/sources.list | sed -n '1,200p' >/dev/null 2>&1 || true
  awk '/^deb /{if(index($0,"universe")==0) {print $0" universe"} else {print $0}} !/^deb /{print $0}' /etc/apt/sources.list > /etc/apt/sources.list.tmp || true
  if [ -f /etc/apt/sources.list.tmp ]; then
    mv /etc/apt/sources.list.tmp /etc/apt/sources.list
  fi
fi

echo "Installing prerequisite packages..."
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common

echo "Installing basic tools and system packages..."
apt-get install -y --no-install-recommends git build-essential nano emacsen-common locales libpam-modules libpam-runtime sudo

# Install supervisor, ssh server and docker compose plugin (we'll avoid systemd)
apt-get install -y --no-install-recommends supervisor openssh-server

# Prevent services from being started during package installation
cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

#### Install Docker CE
echo "Adding Docker repository and GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
echo "Installing docker packages..."
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io
echo "Adding NVIDIA package repositories and GPG key (official method)"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add -

# Determine distro and try a few fallbacks if the exact distro isn't available
OS_ID=$(. /etc/os-release; echo "$ID")
VER=$(. /etc/os-release; echo "$VERSION_ID")
echo "Detected OS: $OS_ID $VER"

#
# Why is this needed? We know what version we're using.
#
declare -a CANDIDATES
CANDIDATES+=("${OS_ID}${VER}")
# Common fallbacks for newer Ubuntu releases that may not yet be published
if [ "${OS_ID}" = "ubuntu" ]; then
  CANDIDATES+=("ubuntu22.04" "ubuntu20.04" "ubuntu18.04")
fi

FOUND=0
for D in "${CANDIDATES[@]}"; do
  URL="https://nvidia.github.io/libnvidia-container/${D}/nvidia-container-toolkit.list"
  echo "Trying NVIDIA repo list: $URL"
  if curl -fsSL "$URL" -o "/etc/apt/sources.list.d/nvidia-container-toolkit.list"; then
    echo "Using NVIDIA repo list for: $D"
    FOUND=1
    break
  fi
done

if [ "$FOUND" -ne 1 ]; then
  echo "Failed to find a suitable NVIDIA container toolkit repo for ${OS_ID} ${VER}" >&2
  exit 1
fi

apt-get update
echo "Installing nvidia-container-toolkit (official package)..."
apt-get install -y --no-install-recommends nvidia-container-toolkit

# Configure the runtime integration This writes config files but does not 
# attempt to restart services (chroot prevents service control).
if command -v nvidia-ctk >/dev/null 2>&1; then
    echo "Configuring NVIDIA container runtime (nvidia-ctk)"
    nvidia-ctk runtime configure --runtime=docker || true
fi

echo "Provisioning complete. Cleaning up apt lists..."
rm -rf /var/lib/apt/lists/*

# Remove policy stub
rm -f /usr/sbin/policy-rc.d

## Create a default non-root user 'ubuntu' with UID 1000 for consistency
if ! id -u ubuntu >/dev/null 2>&1; then
  echo "Creating user ubuntu (uid 1000)"
  adduser --uid 1000 --disabled-password --gecos "" ubuntu || true
  mkdir -p /home/ubuntu
  chown ubuntu:ubuntu /home/ubuntu || true
fi

## Ensure a basic locale file exists for PAM/env
if [ ! -f /etc/default/locale ]; then
  echo 'LANG=C.UTF-8' > /etc/default/locale
fi

# Ensure root directory is accessible to non-root users (fix accidental 0700 roots)
chmod 0755 /

echo "Chroot provisioning finished."

## Configure supervisord to run containerd, dockerd and sshd
cat > /etc/supervisor/conf.d/wsl-services.conf <<'EOF'
[supervisord]
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:containerd]
command=/usr/bin/containerd
stdout_logfile=/var/log/containerd.log
stderr_logfile=/var/log/containerd.err
autorestart=true
priority=10

[program:dockerd]
command=/usr/bin/dockerd --host unix:///run/docker.sock --containerd=/run/containerd/containerd.sock
stdout_logfile=/var/log/dockerd.log
stderr_logfile=/var/log/dockerd.err
autorestart=true
priority=20

[program:sshd]
command=/usr/sbin/sshd -D
stdout_logfile=/var/log/sshd.log
stderr_logfile=/var/log/sshd.err
autorestart=true
priority=30
EOF

# Ensure sshd keys and runtime dirs exist
mkdir -p /var/run/sshd /var/log /run/containerd
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  dpkg-reconfigure openssh-server || true
fi

# Helper to start supervisord and optionally run docker compose commands
cat > /usr/local/bin/start-services <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Start supervisord if not running
if ! pgrep -x supervisord >/dev/null 2>&1; then
  /usr/bin/supervisord -c /etc/supervisor/supervisord.conf || true
  sleep 1
fi

# Wait for containerd and dockerd to appear
for i in {1..10}; do
  if [ -S /run/containerd/containerd.sock ] || [ -S /run/containerd/containerd.sock.ttrpc ]; then
    break
  fi
  sleep 1
done

if [ "$#" -gt 0 ]; then
  # Run docker compose commands passed as args (using docker CLI plugin)
  docker compose "$@"
fi
EOF
chmod +x /usr/local/bin/start-services

## Set ubuntu user password and sudoers
echo "ubuntu:ubuntu" | chpasswd || true
# Allow ubuntu to run the start-services helper (and supervisord) without a password,
# but require a password for other sudo actions (so the bootstrap script runs with
# a password prompt).
cat > /etc/sudoers.d/ubuntu <<'EOF'
# Passwordless for specific service helpers
ubuntu ALL=(ALL) NOPASSWD: /usr/local/bin/start-services, /usr/bin/supervisord
# Allow passworded sudo for all other commands
ubuntu ALL=(ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/ubuntu

## Bake a default wsl.conf so the distro uses metadata and ubuntu as default user
cat > /etc/wsl.conf <<'EOF'
[automount]
root = /mnt/
options = metadata

[user]
default = ubuntu
EOF

## Add profile hook to auto-start supervisord when a regular interactive shell appears
cat > /etc/profile.d/start-supervisord.sh <<'EOF'
#!/usr/bin/env bash
# Start supervisord automatically for interactive non-root shells
case "$-" in
  *i*) :;;
  *) return;;
esac
if [ "$(id -u)" -ne 0 ]; then
  if ! pgrep -x supervisord >/dev/null 2>&1; then
    # start supervisord as root (passwordless sudo configured above)
    sudo /usr/local/bin/start-services >/dev/null 2>&1 &
  fi
fi
EOF
chmod 0755 /etc/profile.d/start-supervisord.sh
