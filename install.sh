#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install mef (binaries, configs, services).

Usage:
  ./install.sh [--force]

Options:
  --force   Overwrite existing config files
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

FORCE="0"
for arg in "$@"; do
  if [[ "${arg}" == "--force" ]]; then
    FORCE="1"
  else
    echo "Unknown option: ${arg}"
    usage
    exit 1
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

install -d /usr/local/sbin
install -m 0755 "${ROOT_DIR}/bin/mefdaemon" /usr/local/sbin/mefdaemon
install -m 0755 "${ROOT_DIR}/bin/mefctl" /usr/local/sbin/mefctl

install -d /etc/mef /etc/mef/rules.d /etc/mef/whitelist

if [[ "${FORCE}" == "1" ]]; then
  if [[ -f /etc/mef/mef.conf ]]; then
    cp /etc/mef/mef.conf "/etc/mef/mef.conf.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  if [[ -f /etc/mef/mef.rules ]]; then
    cp /etc/mef/mef.rules "/etc/mef/mef.rules.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  install -m 0644 "${ROOT_DIR}/conf/mef.conf" /etc/mef/mef.conf
  install -m 0644 "${ROOT_DIR}/conf/mef.rules" /etc/mef/mef.rules
  for f in "${ROOT_DIR}/conf/rules.d"/*.conf; do
    [[ -f "${f}" ]] || continue
    install -m 0644 "${f}" "/etc/mef/rules.d/${f##*/}"
  done
  install -m 0644 "${ROOT_DIR}/conf/whitelist/example.conf" /etc/mef/whitelist/example.conf
else
  if [[ ! -f /etc/mef/mef.conf ]]; then
    install -m 0644 "${ROOT_DIR}/conf/mef.conf" /etc/mef/mef.conf
  fi
  if [[ ! -f /etc/mef/mef.rules ]]; then
    install -m 0644 "${ROOT_DIR}/conf/mef.rules" /etc/mef/mef.rules
  fi
  for f in "${ROOT_DIR}/conf/rules.d"/*.conf; do
    [[ -f "${f}" ]] || continue
    base="${f##*/}"
    if [[ ! -f "/etc/mef/rules.d/${base}" ]]; then
      install -m 0644 "${f}" "/etc/mef/rules.d/${base}"
    fi
  done
  if [[ ! -f /etc/mef/whitelist/example.conf ]]; then
    install -m 0644 "${ROOT_DIR}/conf/whitelist/example.conf" /etc/mef/whitelist/example.conf
  fi
fi

if [[ "${OS}" == "Linux" ]]; then
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    install -m 0644 "${ROOT_DIR}/services/systemd/mefdaemon.service" /etc/systemd/system/mefdaemon.service
    systemctl daemon-reload
    systemctl enable --now mefdaemon.service
    systemctl restart mefdaemon.service
  else
    echo "[!] systemd not detected. Run manually: /usr/local/sbin/mefdaemon"
  fi
elif [[ "${OS}" == "FreeBSD" ]]; then
  install -m 0755 "${ROOT_DIR}/services/freebsd/mefdaemon.rc" /usr/local/etc/rc.d/mefdaemon
  if ! grep -q '^mefdaemon_enable=' /etc/rc.conf; then
    echo 'mefdaemon_enable="YES"' >> /etc/rc.conf
  fi
  service mefdaemon restart || service mefdaemon start
else
  echo "Unsupported OS: ${OS}"
  exit 1
fi

echo "[+] Installed"
