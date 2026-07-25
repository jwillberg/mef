#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uninstall mef binaries and services.

Usage:
  ./uninstall.sh [--purge]

Options:
  --purge   Remove /etc/mef and /var/lib/mef
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

PURGE="0"
for arg in "$@"; do
  if [[ "${arg}" == "--purge" ]]; then
    PURGE="1"
  else
    echo "Unknown option: ${arg}"
    usage
    exit 1
  fi
done

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
    echo "This script must run as root."
    exit 1
  fi
}

require_root "$@"

OS="$(uname -s)"

if [[ "${OS}" == "Linux" ]]; then
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl stop mefdaemon.service || true
    systemctl disable mefdaemon.service || true
    rm -f /etc/systemd/system/mefdaemon.service
    rm -f /usr/lib/systemd/system/mefdaemon.service
    rm -f /lib/systemd/system/mefdaemon.service
    systemctl daemon-reload
    systemctl reset-failed || true
  fi
  rm -f /etc/logrotate.d/mef
elif [[ "${OS}" == "FreeBSD" ]]; then
  service mefdaemon stop || true
  rm -f /usr/local/etc/rc.d/mefdaemon
else
  echo "Unsupported OS: ${OS}"
  exit 1
fi

rm -f /usr/local/sbin/mefdaemon
rm -f /usr/local/sbin/mefctl

if [[ "${PURGE}" == "1" ]]; then
  rm -rf /etc/mef
  rm -rf /var/lib/mef || true
fi

echo "[+] Uninstalled"
