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
    # Install both services
    install -m 0644 "${ROOT_DIR}/services/systemd/mef.service" /etc/systemd/system/mef.service
    install -m 0644 "${ROOT_DIR}/services/systemd/mefdaemon.service" /etc/systemd/system/mefdaemon.service
    systemctl daemon-reload
    
    echo ""
    echo "[+] Two services installed:"
    echo "    mef.service       - persistent firewall rules (from /etc/mef/mef.rules)"
    echo "    mefdaemon.service - dynamic IP banning (fail2ban-style)"
    echo ""
    echo "⚠️  IMPORTANT: Firewall rules NOT enabled by default to prevent lockout!"
    echo ""
    echo "BEFORE enabling mef.service:"
    echo "  1. Edit /etc/mef/mef.rules to match your network"
    echo "  2. Verify SSH access will be allowed from your IP"
    echo "  3. Test rules: mefctl rules validate"
    echo "  4. Apply with rollback: mefctl rules apply (type 'yes' within 30s)"
    echo "  5. If access OK, enable service: systemctl enable mef.service"
    echo ""
    echo "Starting mefdaemon only (auto-banning)..."
    systemctl enable --now mefdaemon.service
    echo "[+] mefdaemon.service started"
  else
    echo "[!] systemd not detected. Run manually:"
    echo "    /usr/local/sbin/mefctl rules apply --yes /etc/mef/mef.rules"
    echo "    /usr/local/sbin/mefdaemon"
  fi
elif [[ "${OS}" == "FreeBSD" ]]; then
  # Install both rc.d scripts
  install -m 0755 "${ROOT_DIR}/services/freebsd/mef" /usr/local/etc/rc.d/mef
  install -m 0755 "${ROOT_DIR}/services/freebsd/mefdaemon" /usr/local/etc/rc.d/mefdaemon
  
  echo ""
  echo "[+] Two services installed:"
  echo "    mef       - persistent firewall rules (from /etc/mef/mef.rules)"
  echo "    mefdaemon - dynamic IP banning (fail2ban-style)"
  echo ""
  echo "⚠️  IMPORTANT: Firewall rules NOT enabled by default to prevent lockout!"
  echo ""
  echo "BEFORE enabling mef:"
  echo "  1. Edit /etc/mef/mef.rules to match your network"
  echo "  2. Verify SSH access will be allowed from your IP"
  echo "  3. Test rules: mefctl rules validate"
  echo "  4. Apply with rollback: mefctl rules apply (type 'yes' within 30s)"
  echo "  5. If access OK, enable service: sysrc mef_enable=YES && service mef start"
  echo ""
  echo "Starting mefdaemon only (auto-banning)..."
  if ! grep -q '^mefdaemon_enable=' /etc/rc.conf; then
    echo 'mefdaemon_enable="YES"' >> /etc/rc.conf
  fi
  service mefdaemon restart || service mefdaemon start
  echo "[+] mefdaemon started"
else
  echo "Unsupported OS: ${OS}"
  exit 1
fi

echo ""
echo "[+] Installation complete"
echo ""
