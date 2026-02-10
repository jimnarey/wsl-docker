#!/usr/bin/env bash
set -euo pipefail

# provision/bootstrap.sh
# To be run inside the imported WSL distribution. Can be run multiple times without harm. 
# configuration. Intended to be run as root (the PowerShell installer runs this via
# `wsl -d <distro> -- bash /bootstrap.sh`).

NEW_USER=${NEW_USER:-developer}
REPO_URL=${REPO_URL:-}
REPO_DEST=${REPO_DEST:-/home/${NEW_USER}/app}

echo "Bootstrap starting: configuring runtimes and optional repo clone"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script should be run as root. Re-run as root or via sudo." >&2
  exit 2
fi

# Create non-root user if requested and not exists
if ! id -u "$NEW_USER" >/dev/null 2>&1; then
  echo "Creating user $NEW_USER"
  adduser --disabled-password --gecos "" "$NEW_USER" || true
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

# Restart container runtimes (systemd if available, otherwise service commands)
SVCS="docker containerd"
INIT_PID1=$(ps -p 1 -o comm= | tr -d '[:space:]') || INIT_PID1=""
if [ "$INIT_PID1" = "systemd" ]; then
  echo "Restarting services via systemctl: $SVCS"
  for s in $SVCS; do
    if systemctl list-unit-files | grep -q "^$s"; then
      systemctl restart "$s" || true
    fi
  done
else
  echo "systemd not detected; attempting service restart"
  for s in $SVCS; do
    if command -v service >/dev/null 2>&1; then
      service "$s" restart || true
    fi
  done
fi

# Optional: clone a repository containing Dockerfiles/compose
if [ -n "$REPO_URL" ]; then
  echo "REPO_URL provided; cloning to $REPO_DEST"
  mkdir -p "$(dirname "$REPO_DEST")"
  if [ ! -d "$REPO_DEST/.git" ]; then
    git clone "$REPO_URL" "$REPO_DEST" || echo "git clone failed"
    chown -R "$NEW_USER":"$NEW_USER" "$REPO_DEST" || true
  else
    echo "Repository already present at $REPO_DEST; pulling latest"
    (cd "$REPO_DEST" && git pull) || true
  fi
fi

echo "Bootstrap finished"
exit 0
