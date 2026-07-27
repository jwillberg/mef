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

resolve_ban_log_path() {
  local cfg="/etc/mef/mef.conf"
  local path="/var/log/mef.log"
  if [[ -f "${cfg}" ]]; then
    local parsed
    parsed="$(awk '
      BEGIN { in_global=0 }
      /^[[:space:]]*\[/ {
        sec=$0
        gsub(/^[[:space:]]*\[/, "", sec)
        gsub(/\][[:space:]]*$/, "", sec)
        in_global=(tolower(sec)=="global")
        next
      }
      {
        line=$0
        sub(/[;#].*$/, "", line)
      }
      in_global && line ~ /^[[:space:]]*ban_log_path[[:space:]]*=/ {
        sub(/^[[:space:]]*ban_log_path[[:space:]]*=[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    ' "${cfg}" 2>/dev/null || true)"
    if [[ -n "${parsed}" ]]; then
      path="${parsed}"
    fi
  fi
  printf '%s\n' "${path}"
}

install_linux_logrotate_policy() {
  local log_path="$1"
  if ! command -v logrotate >/dev/null 2>&1; then
    echo "[!] logrotate not found; skipping /etc/logrotate.d/mef policy install"
    return 0
  fi

  install -d /etc/logrotate.d
  cat >/etc/logrotate.d/mef <<EOF
${log_path} {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
            systemctl kill -s HUP mefdaemon.service >/dev/null 2>&1 || true
        fi
    endscript
}
EOF
  chmod 0644 /etc/logrotate.d/mef
  echo "[+] Installed logrotate policy: /etc/logrotate.d/mef (log=${log_path})"
}

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
ARCH="$(uname -m)"

# Map architecture to build suffix
ARCH_SUFFIX=""
case "${ARCH}" in
  x86_64) ARCH_SUFFIX="amd64" ;;
  aarch64) ARCH_SUFFIX="arm64" ;;
  arm64) ARCH_SUFFIX="arm64" ;;  # macOS M1/M2
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
  ;;
esac

# Map OS to build suffix
OS_SUFFIX=""
case "${OS}" in
  Linux) OS_SUFFIX="linux" ;;
  FreeBSD) OS_SUFFIX="freebsd" ;;
  Darwin) OS_SUFFIX="darwin" ;;
  *)
    echo "Unsupported OS: ${OS}"
    exit 1
  ;;
esac

# Select the exact OS/architecture binaries on every supported platform.
MEFDAEMON_BIN="${ROOT_DIR}/bin/mefdaemon_${OS_SUFFIX}_${ARCH_SUFFIX}"
MEFCTL_BIN="${ROOT_DIR}/bin/mefctl_${OS_SUFFIX}_${ARCH_SUFFIX}"

# Verify binaries exist
if [[ ! -f "${MEFDAEMON_BIN}" ]]; then
  echo "ERROR: mefdaemon binary not found: ${MEFDAEMON_BIN}"
  echo "Available binaries:"
  ls -la "${ROOT_DIR}/bin/" 2>/dev/null || echo "  (bin/ directory empty)"
  exit 1
fi
if [[ ! -f "${MEFCTL_BIN}" ]]; then
  echo "ERROR: mefctl binary not found: ${MEFCTL_BIN}"
  echo "Available binaries:"
  ls -la "${ROOT_DIR}/bin/" 2>/dev/null || echo "  (bin/ directory empty)"
  exit 1
fi

install -d /usr/local/sbin
install -m 0755 "${MEFDAEMON_BIN}" /usr/local/sbin/mefdaemon
install -m 0755 "${MEFCTL_BIN}" /usr/local/sbin/mefctl

install -d /etc/mef /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist /etc/mef/cache /etc/mef/webscan.d
touch /etc/mef/blacklist/auto-permanent.conf

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
  install -m 0644 "${ROOT_DIR}/conf/blacklist/example.conf" /etc/mef/blacklist/example.conf
  for f in "${ROOT_DIR}/conf/webscan.d"/*.conf; do
    [[ -f "${f}" ]] || continue
    install -m 0644 "${f}" "/etc/mef/webscan.d/${f##*/}"
  done
  touch /etc/mef/blacklist/auto-permanent.conf
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
  if [[ ! -f /etc/mef/blacklist/example.conf ]]; then
    install -m 0644 "${ROOT_DIR}/conf/blacklist/example.conf" /etc/mef/blacklist/example.conf
  fi
  for f in "${ROOT_DIR}/conf/webscan.d"/*.conf; do
    [[ -f "${f}" ]] || continue
    base="${f##*/}"
    if [[ ! -f "/etc/mef/webscan.d/${base}" ]]; then
      install -m 0644 "${f}" "/etc/mef/webscan.d/${base}"
    fi
  done
  if [[ ! -f /etc/mef/blacklist/auto-permanent.conf ]]; then
    touch /etc/mef/blacklist/auto-permanent.conf
  fi
fi

if [[ "${OS}" == "Linux" ]]; then
  BAN_LOG_PATH="$(resolve_ban_log_path)"
  install_linux_logrotate_policy "${BAN_LOG_PATH}"

  PSD_CONNTRACK_HINT="install package providing 'conntrack' (often: conntrack or conntrack-tools)"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_release_blob="${ID:-} ${ID_LIKE:-}"
    if [[ "${os_release_blob}" == *"debian"* || "${os_release_blob}" == *"ubuntu"* ]]; then
      PSD_CONNTRACK_HINT="apt install conntrack"
    elif [[ "${os_release_blob}" == *"rhel"* || "${os_release_blob}" == *"centos"* || "${os_release_blob}" == *"rocky"* || "${os_release_blob}" == *"alma"* || "${os_release_blob}" == *"fedora"* ]]; then
      PSD_CONNTRACK_HINT="dnf install conntrack-tools (or yum install conntrack-tools)"
    fi
  fi

  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    # Install both services
    install -m 0644 "${ROOT_DIR}/services/systemd/mef.service" /etc/systemd/system/mef.service
    install -m 0644 "${ROOT_DIR}/services/systemd/mefdaemon.service" /etc/systemd/system/mefdaemon.service
    systemctl daemon-reload
    
    # Both services disabled by default (user must enable manually)
    systemctl disable mef.service || true
    systemctl disable mefdaemon.service || true
    
    echo ""
    echo "[+] Two services installed (both DISABLED by default):"
    echo "    mef.service       - persistent firewall rules (from /etc/mef/mef.rules)"
    echo "    mefdaemon.service - dynamic IP banning (fail2ban-style)"
    echo ""
    echo "⚠️  IMPORTANT: Both services are disabled to prevent accidental lockout!"
    echo ""
    echo "Next steps:"
    echo "  1. Review and test /etc/mef/mef.rules:"
    echo "     - Verify SSH port 22 is open from your IP"
    echo "     - Run: mefctl rules validate"
    echo "  2. Enable and test firewall rules:"
    echo "     - Run: mefctl rules apply (30-second rollback window)"
    echo "     - Type 'yes' to keep rules if SSH access works"
    echo "  3. Enable services for boot:"
    echo "     - mef.service: mefctl enable mef"
    echo "     - mefdaemon.service: mefctl enable mefdaemon"
    echo "  4. Verify boot activation:"
    echo "     - Run: mefctl status"
    echo ""
    echo "PSD note (optional feature):"
    if command -v conntrack >/dev/null 2>&1; then
      echo "  - conntrack command found (PSD primary source available)"
    else
      echo "  - conntrack command missing (PSD primary source unavailable)"
      echo "  - Install with: ${PSD_CONNTRACK_HINT}"
      echo "  - Or use journal fallback: firewall_log_enabled=true"
    fi
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
  echo "[+] Two services installed (both DISABLED by default):"
  echo "    mef       - persistent firewall rules (from /etc/mef/mef.rules)"
  echo "    mefdaemon - dynamic IP banning (fail2ban-style)"
  echo ""
  echo "⚠️  IMPORTANT: Both services are disabled to prevent accidental lockout!"
  echo ""
  echo "Next steps:"
  echo "  1. Review and test /etc/mef/mef.rules:"
  echo "     - Verify SSH port 22 is open from your IP"
  echo "     - Run: mefctl rules validate"
  echo "  2. Enable and test firewall rules:"
  echo "     - Run: mefctl rules apply (30-second rollback window)"
  echo "     - Type 'yes' to keep rules if SSH access works"
  echo "  3. Enable services for boot:"
  echo "     - mef: mefctl enable mef"
  echo "     - mefdaemon: mefctl enable mefdaemon"
  echo "  4. Verify boot activation:"
  echo "     - Run: mefctl status"
else
  echo "Unsupported OS: ${OS}"
  exit 1
fi

echo ""
echo "[+] Installation complete"
echo ""
