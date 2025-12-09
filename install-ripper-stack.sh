#!/usr/bin/env bash
set -euo pipefail

# Simple installer for a DVD/Blu-ray ripping VM on Ubuntu/Debian
# - Installs MakeMKV (via PPA)
# - Installs HandBrake CLI + ffmpeg
# - Installs libdvdcss via libdvd-pkg
# - Installs Python for helper scripts

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo ./install-ripper-stack.sh)" >&2
  exit 1
fi

echo "[*] Updating system packages..."
apt update
apt upgrade -y

echo "[*] Installing base tools..."
apt install -y \
  software-properties-common \
  curl wget gnupg lsb-release \
  handbrake-cli ffmpeg \
  python3 python3-venv python3-pip \
  libdvd-pkg regionset

echo "[*] Configuring libdvdcss (via libdvd-pkg)..."
dpkg-reconfigure libdvd-pkg

echo "[*] Adding MakeMKV PPA..."
add-apt-repository -y ppa:heyarje/makemkv-beta
apt update

echo "[*] Installing MakeMKV..."
apt install -y makemkv-bin makemkv-oss

echo "[*] Adding current user to cdrom group..."
CURRENT_USER=${SUDO_USER:-$(whoami)}
usermod -aG cdrom "$CURRENT_USER"

cat <<EOF

[+] Done.

Next steps:
  1) Log out / back in so 'cdrom' group membership takes effect.
  2) Run 'regionset /dev/sr0' ONCE to set your DVD drive region.
  3) Start MakeMKV GUI at least once (if you want) to enter the beta/paid key.
  4) Place the rip scripts somewhere like /opt/ripper and make them executable.

EOF
