#!/usr/bin/env bash
set -euo pipefail

# provision/bootstrap.sh
# To be run inside the imported WSL distribution. Can be run multiple times without harm. 
# configuration. Intended to be run as root (the PowerShell installer runs this via
# `wsl -d <distro> -- bash /bootstrap.sh`).

NEW_USER=${NEW_USER:-ubuntu}
REPO_URL=${REPO_URL:-}
REPO_DEST=${REPO_DEST:-/home/${NEW_USER}/app}

echo "Bootstrap starting: configuring runtimes and optional repo clone"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script should be run as root. Re-run as root or via sudo." >&2
  exit 2
fi


# Ensure /home/$NEW_USER exists and is owned by the correct user (idempotent)
if [ ! -d "/home/$NEW_USER" ]; then
  mkdir -p "/home/$NEW_USER"
  chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER"
else
  # Fix ownership if needed
  owner=$(stat -c '%U' "/home/$NEW_USER" 2>/dev/null || echo '')
  group=$(stat -c '%G' "/home/$NEW_USER" 2>/dev/null || echo '')
  if [ "$owner" != "$NEW_USER" ] || [ "$group" != "$NEW_USER" ]; then
    chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER"
  fi
fi

# Ensure user is in docker group
if command -v groupadd >/dev/null 2>&1; then
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || true
  fi
  usermod -aG docker "$NEW_USER" || true
fi

# Configure NVIDIA container toolkit runtimes if available
if command -v nvidia-ctk >/dev/null 2>&1; then
  echo "Configuring NVIDIA container toolkit runtimes"
  for rt in docker containerd; do
    echo "nvidia-ctk runtime configure --runtime=$rt"
    nvidia-ctk runtime configure --runtime="$rt" || true
  done
fi

# We intentionally do not use systemd in this image. Instead we ship a
# supervisord configuration and a helper `/usr/local/bin/start-services`
# which will start containerd, dockerd and sshd, and can optionally run
# `docker compose` commands passed as arguments.

echo "Bootstrap finished. Services will be started automatically when an interactive non-root shell is opened."
echo "To start services manually run: /usr/local/bin/start-services [compose-args]"
exit 0
