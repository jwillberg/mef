#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Update mef binaries using updates.json metadata.

Usage:
  ./update.sh [--force] [--version X.Y.Z]

Options:
  --force           Reinstall same version / allow downgrade
  --version X.Y.Z   Install specific version (bounded by min_version/latest_version)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

ORIGINAL_ARGS=("$@")
FORCE="0"
REQUESTED_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE="1"
      shift
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --version"
        exit 1
      fi
      REQUESTED_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "${ORIGINAL_ARGS[@]}"
    fi
    echo "This script must run as root."
    exit 1
  fi
}

require_root "$@"

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing dependency: curl"
  exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

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

ARCH_SUFFIX=""
case "${ARCH}" in
  x86_64) ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

ASSET_KEY="${OS_SUFFIX}_${ARCH_SUFFIX}"
METADATA_URLS=(
  "https://raw.githubusercontent.com/jwillberg/mef/refs/heads/main/updates.json"
  "https://raw.githubusercontent.com/jwillberg/mef/main/updates.json"
  "https://github.com/jwillberg/mef/raw/refs/heads/main/updates.json"
)

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
    echo "warning: logrotate not found; skipping /etc/logrotate.d/mef policy update"
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
  echo "Updated logrotate policy: /etc/logrotate.d/mef (log=${log_path})"
}

normalize_version() {
  local v="${1#v}"
  if [[ ! "${v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([.-].*)?$ ]]; then
    return 1
  fi
  echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
}

semver_cmp() {
  local a b
  a="$(normalize_version "$1")" || return 1
  b="$(normalize_version "$2")" || return 1
  IFS='.' read -r a1 a2 a3 <<<"${a}"
  IFS='.' read -r b1 b2 b3 <<<"${b}"
  if (( a1 < b1 )); then echo -1; return 0; fi
  if (( a1 > b1 )); then echo 1; return 0; fi
  if (( a2 < b2 )); then echo -1; return 0; fi
  if (( a2 > b2 )); then echo 1; return 0; fi
  if (( a3 < b3 )); then echo -1; return 0; fi
  if (( a3 > b3 )); then echo 1; return 0; fi
  echo 0
}

json_get_string() {
  local json="$1"
  local key="$2"
  printf '%s' "${json}" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}

json_get_asset_url() {
  local json="$1"
  local key="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$key" "$json" <<'PY'
import json
import sys

asset_key = sys.argv[1]
raw = sys.argv[2]
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(1)
assets = doc.get("assets") or {}
entry = assets.get(asset_key) or {}
url = str(entry.get("url") or "").strip()
if url:
    print(url)
PY
    return 0
  fi
  awk -v key="\"${key}\"" '
    $0 ~ key"[[:space:]]*:[[:space:]]*\\{" {in_asset=1; next}
    in_asset && /"url"[[:space:]]*:/ {
      if (match($0, /"url"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) {
        print m[1]
        exit 0
      }
    }
    in_asset && /}/ {in_asset=0}
  ' <<<"${json}"
}

fetch_metadata() {
  local out=""
  local url
  for url in "${METADATA_URLS[@]}"; do
    echo "Checking update metadata: ${url}" >&2
    if out="$(curl -fsSL --connect-timeout 10 --max-time 30 "${url}")"; then
      echo "${out}"
      return 0
    fi
  done
  return 1
}

CURRENT_VERSION=""
if [[ -x /usr/local/sbin/mefctl ]]; then
  CURRENT_VERSION="$(/usr/local/sbin/mefctl --help 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {print $i; exit}}')"
fi

METADATA="$(fetch_metadata)" || {
  echo "update failed: fetch metadata"
  exit 1
}

LATEST_VERSION="$(json_get_string "${METADATA}" "latest_version")"
MIN_VERSION="$(json_get_string "${METADATA}" "min_version")"
if [[ -z "${LATEST_VERSION}" || -z "${MIN_VERSION}" ]]; then
  echo "update failed: invalid updates.json (missing latest_version/min_version)"
  exit 1
fi

LATEST_VERSION="$(normalize_version "${LATEST_VERSION}")" || {
  echo "update failed: invalid latest_version in updates.json"
  exit 1
}
MIN_VERSION="$(normalize_version "${MIN_VERSION}")" || {
  echo "update failed: invalid min_version in updates.json"
  exit 1
}

TARGET_VERSION="${LATEST_VERSION}"
if [[ -n "${REQUESTED_VERSION}" ]]; then
  TARGET_VERSION="$(normalize_version "${REQUESTED_VERSION}")" || {
    echo "update failed: invalid --version ${REQUESTED_VERSION}"
    exit 1
  }
fi

cmp_min="$(semver_cmp "${TARGET_VERSION}" "${MIN_VERSION}")" || {
  echo "update failed: semver compare failed"
  exit 1
}
if (( cmp_min < 0 )); then
  echo "update failed: requested version ${TARGET_VERSION} is below minimum ${MIN_VERSION}"
  exit 1
fi

cmp_latest="$(semver_cmp "${TARGET_VERSION}" "${LATEST_VERSION}")" || {
  echo "update failed: semver compare failed"
  exit 1
}
if (( cmp_latest > 0 )); then
  echo "update failed: requested version ${TARGET_VERSION} is newer than latest ${LATEST_VERSION}"
  exit 1
fi

if [[ -n "${CURRENT_VERSION}" ]]; then
  if cur_cmp="$(semver_cmp "${CURRENT_VERSION}" "${TARGET_VERSION}")"; then
    if (( cur_cmp == 0 )) && [[ "${FORCE}" != "1" ]]; then
      echo "Already at target version (current=${CURRENT_VERSION} target=${TARGET_VERSION}). Use --force to reinstall."
      exit 0
    fi
    if (( cur_cmp > 0 )) && [[ "${FORCE}" != "1" ]]; then
      echo "update failed: downgrade ${CURRENT_VERSION} -> ${TARGET_VERSION} requires --force"
      exit 1
    fi
  fi
fi

DAEMON_URL="$(json_get_asset_url "${METADATA}" "${ASSET_KEY}")"
if [[ -z "${DAEMON_URL}" ]]; then
  DAEMON_URL="https://github.com/jwillberg/mef/raw/refs/tags/v${TARGET_VERSION}/bin/mefdaemon_${ASSET_KEY}"
fi

DAEMON_CANDIDATES=(
  "${DAEMON_URL}"
  "https://github.com/jwillberg/mef/raw/refs/tags/v${TARGET_VERSION}/bin/mefdaemon_${ASSET_KEY}"
  "https://raw.githubusercontent.com/jwillberg/mef/v${TARGET_VERSION}/bin/mefdaemon_${ASSET_KEY}"
  "https://github.com/jwillberg/mef/raw/refs/heads/main/bin/mefdaemon_${ASSET_KEY}"
)

CTL_FROM_DAEMON="${DAEMON_URL/mefdaemon_${ASSET_KEY}/mefctl_${ASSET_KEY}}"
if [[ "${CTL_FROM_DAEMON}" == "${DAEMON_URL}" ]]; then
  CTL_FROM_DAEMON=""
fi

CTL_CANDIDATES=(
  "${CTL_FROM_DAEMON}"
  "https://github.com/jwillberg/mef/raw/refs/tags/v${TARGET_VERSION}/bin/mefctl_${ASSET_KEY}"
  "https://raw.githubusercontent.com/jwillberg/mef/v${TARGET_VERSION}/bin/mefctl_${ASSET_KEY}"
  "https://github.com/jwillberg/mef/raw/refs/heads/main/bin/mefctl_${ASSET_KEY}"
)

dedupe_urls() {
  local seen=""
  local out=()
  local u
  for u in "$@"; do
    [[ -n "${u}" ]] || continue
    if [[ ",${seen}," == *",${u},"* ]]; then
      continue
    fi
    seen="${seen},${u}"
    out+=("${u}")
  done
  printf '%s\n' "${out[@]}"
}

is_executable_payload() {
  local file="$1"
  local magic
  magic="$(LC_ALL=C od -An -tx1 -N4 "${file}" | tr -d ' \n' || true)"
  case "${magic}" in
    7f454c46|feedface|feedfacf|cefaedfe|cffaedfe)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

download_first_ok() {
  local name="$1"
  local out="$2"
  shift 2
  local url
  local first=""
  local used=""
  for url in "$@"; do
    [[ -n "${first}" ]] || first="${url}"
    if curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 -o "${out}" "${url}"; then
      if ! is_executable_payload "${out}"; then
        continue
      fi
      used="${url}"
      break
    fi
  done
  if [[ -z "${used}" ]]; then
    echo "update failed: download ${name}: all candidate URLs failed"
    return 1
  fi
  echo "Downloading ${name}: ${first}"
  if [[ "${used}" != "${first}" ]]; then
    echo "Download fallback source selected for ${name}: ${used}"
  fi
  return 0
}

mapfile -t DAEMON_URLS < <(dedupe_urls "${DAEMON_CANDIDATES[@]}")
mapfile -t CTL_URLS < <(dedupe_urls "${CTL_CANDIDATES[@]}")

if [[ ${#DAEMON_URLS[@]} -eq 0 || ${#CTL_URLS[@]} -eq 0 ]]; then
  echo "update failed: no download URLs resolved for ${ASSET_KEY}"
  exit 1
fi

echo "Update plan: current=${CURRENT_VERSION:-unknown} target=${TARGET_VERSION} latest=${LATEST_VERSION} min=${MIN_VERSION}"
if [[ "${FORCE}" == "1" ]]; then
  echo "Force mode enabled."
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

DAEMON_TMP="${TMP_DIR}/mefdaemon"
CTL_TMP="${TMP_DIR}/mefctl"

download_first_ok "mefdaemon" "${DAEMON_TMP}" "${DAEMON_URLS[@]}"
download_first_ok "mefctl" "${CTL_TMP}" "${CTL_URLS[@]}"

install -d /usr/local/sbin
install -m 0755 "${DAEMON_TMP}" /usr/local/sbin/mefdaemon
install -m 0755 "${CTL_TMP}" /usr/local/sbin/mefctl

restart_ok="0"
if [[ "${OS}" == "Linux" ]]; then
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    if systemctl restart mefdaemon.service; then
      echo "Restarted mefdaemon.service"
      restart_ok="1"
    fi
  fi
  if [[ "${restart_ok}" != "1" ]] && command -v service >/dev/null 2>&1; then
    if service mefdaemon restart; then
      echo "Restarted mefdaemon"
      restart_ok="1"
    fi
  fi
elif [[ "${OS}" == "FreeBSD" ]]; then
  if service mefdaemon restart; then
    echo "Restarted mefdaemon"
    restart_ok="1"
  fi
fi

if [[ "${restart_ok}" != "1" ]]; then
  echo "warning: failed to restart mefdaemon automatically"
fi

if [[ "${OS}" == "Linux" ]]; then
  BAN_LOG_PATH="$(resolve_ban_log_path)"
  install_linux_logrotate_policy "${BAN_LOG_PATH}"
fi

echo "Update complete. Installed version target=${TARGET_VERSION}"
echo "Note: re-run 'mefctl --help' to verify the new mefctl banner version."
