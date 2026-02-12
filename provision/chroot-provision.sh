#!/bin/bash
set -euo pipefail

# Minimal chroot provisioner to install Docker CE and NVIDIA container toolkit
# Run inside a chroot (root is the target rootfs)

export DEBIAN_FRONTEND=noninteractive

echo "Installing prerequisite packages..."
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common

echo "Installing basic tools..."
apt-get install -y --no-install-recommends git build-essential nano emacs

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

echo "Chroot provisioning finished."
