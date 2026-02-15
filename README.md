# mef

**mef (Malware.Expert Firewall)** is a lightweight Linux firewall and automatic IP ban engine.

It combines:
- **Persistent firewall management** (nftables preferred, iptables fallback)
- **Fail2ban-style log monitoring and automatic IP blocking**
- Native **systemd / FreeBSD service integration**

Designed as a simple, modern alternative to UFW, CSF and Fail2Ban stacks.

## Two Independent Services

mef consists of two standalone services that work together or separately:

### 1. **mef** (firewall rules service)
- Loads persistent firewall policy rules from `/etc/mef/mef.rules`
- Runs once at boot (oneshot service)
- Use this if you want permanent firewall rules
- Works with nftables or iptables backends

### 2. **mefdaemon** (auto-ban service)
- Monitors logs (journal/files) for failed authentication attempts
- Automatically bans offending IPs (fail2ban-style)
- Runs continuously as a daemon
- Per-service rules in `/etc/mef/rules.d/*.conf`

**Both services are independent** - you can use:
- Both together (firewall + auto-banning)
- Only mefdaemon (fail2ban replacement)
- Only mef (persistent firewall rules)

## What is it?
- **Firewall management** without complex rule syntax (`mef.rules`)
- **Automatic IP bans** from logs (SSH, Postfix, etc.)
- **Nftables first**, iptables fallback
- **Lightweight and scalable**, no libsystemd dependency

## Who is it for?
- Servers that want a **simple** and **clear** firewall + auto‑ban setup
- A lightweight alternative to UFW/CSF/Fail2Ban‑style stacks

## Highlights
- Journal **and** file log inputs (`source=journal/file`)
- One clear config per service (no separate jail/filter)
- Bans via nftables/iptables backends
- Safe defaults, easy install

## Architecture

mef is split into two independent components:

- **mef** → firewall rules loader (persistent policy service)
- **mefdaemon** → log parser + dynamic IP ban engine

Firewall backends:
- nftables (primary)
- iptables (fallback)

The daemon maintains in-memory IP sets and updates firewall rules dynamically.

## Install

⚠️ **IMPORTANT:** Both services are **disabled by default** to prevent accidental lockout. You must enable them manually after testing.

### Quick install (after extract)
```bash
cd /tmp/mef-release
chmod +x install.sh uninstall.sh
sudo ./install.sh

# After install - both services are DISABLED by default
# Test firewall rules first:
mefctl rules validate
mefctl rules apply    # 30-second rollback window, type "yes" if SSH works

# When SSH access is verified, enable services:
mefctl enable mef           # Enable firewall rules at boot
mefctl enable mefdaemon     # Enable auto-banning at boot
# Or enable both: mefctl enable

# Verify they're enabled:
mefctl status
```

For uninstall:
```bash
sudo ./uninstall.sh
```

### Download & extract (example)
```bash
# Replace URL and archive name as needed
curl -LO https://github.com/jwillberg/mef/releases/download/v1.0.0/mef-release.tar.gz
tar -xzf mef-release.tar.gz -C /tmp
cd /tmp/mef-release
```

### Manual install
#### Linux (systemd, Debian/Ubuntu/RHEL/Fedora)
```bash
sudo mkdir -p /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist /etc/mef/cache
sudo cp -f bin/mefdaemon /usr/local/sbin/mefdaemon
sudo cp -f bin/mefctl /usr/local/sbin/mefctl
sudo chmod 0755 /usr/local/sbin/mefdaemon /usr/local/sbin/mefctl

sudo cp -n conf/mef.conf /etc/mef/mef.conf
sudo cp -n conf/mef.rules /etc/mef/mef.rules
sudo cp -n conf/rules.d/*.conf /etc/mef/rules.d/
sudo cp -n conf/whitelist/example.conf /etc/mef/whitelist/example.conf
sudo cp -n conf/blacklist/example.conf /etc/mef/blacklist/example.conf

# Install both services (both DISABLED by default)
sudo cp -f services/systemd/mef.service /etc/systemd/system/mef.service
sudo cp -f services/systemd/mefdaemon.service /etc/systemd/system/mefdaemon.service
sudo systemctl daemon-reload

# Both services are disabled by default to prevent lockout
# Test firewall rules first:
mefctl rules validate
mefctl rules apply    # 30-second rollback window, type "yes" if SSH works

# When SSH access is verified, enable services:
mefctl enable mef           # Enable firewall rules at boot
mefctl enable mefdaemon     # Enable auto-banning at boot

# Verify they're enabled:
mefctl status
```

#### FreeBSD
```sh
sudo install -d /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist /etc/mef/cache
sudo install -m 0755 bin/mefdaemon /usr/local/sbin/mefdaemon
sudo install -m 0755 bin/mefctl /usr/local/sbin/mefctl
sudo install -m 0644 conf/mef.conf /etc/mef/mef.conf
sudo install -m 0644 conf/mef.rules /etc/mef/mef.rules
sudo install -m 0644 conf/ru (both DISABLED by default)
sudo install -m 0755 services/freebsd/mef /usr/local/etc/rc.d/mef
sudo install -m 0755 services/freebsd/mefdaemon /usr/local/etc/rc.d/mefdaemon

# Both services are disabled by default to prevent lockout
# Test firewall rules first:
mefctl rules validate
mefctl rules apply    # 30-second rollback window, type "yes" if SSH works

# When SSH access is verified, enable services:
mefctl enable mef           # Enable firewall rules at boot
mefctl enable mefdaemon     # Enable auto-banning at boot

# Verify they're enabled:
mefctl status
# 2. Test: mefctl rules validate
# 3. Apply with rollback: mefctl rules apply (type "yes" within 30s)
# 4. If SSH works, enable: sudo sysrc mef_enable=YES && sudo service mef start
```
 (via mefctl)
```bash
mefctl status                 # Show service status (enabled/running)
mefctl enable [mef|mefdaemon] # Enable service(s) to start at boot (both if none specified)
mefctl disable [mef|mefdaemon]# Disable service(s) from starting at boot
mefctl start mef|mefdaemon    # Start service immediately
mefctl stop mef|mefdaemon     # Stop service immediately
```

### Service Management (via systemctl/service)
## Commands
### Service Management
```bash
# systemd (Linux)
systemctl status mef mefdaemon
systemctl reload mef          # Reload firewall rules
systemctl reload mefdaemon    # Reload daemon config + flush bans

# FreeBSD
service mef status
service mefdaemon status
service mef reload            # Reload firewall rules
service mefdaemon reload      # Reload daemon config
```

### Firewall Rules (mefctl)
```bash
mefctl rules validate         # Check /etc/mef/mef.rules syntax
mefctl rules apply            # Apply rules (with rollback confirmation)
mefctl rules apply --yes      # Apply rules (no confirmation, for service)
mefctl rules clear            # Clear mef firewall rules
mefctl rules clear --all --force  # Clear entire nftables table
```

### Ban Management (mefctl)
```bash
mefctl bans list              # Show all banned IPs
mefctl bans add <ip>          # Manually ban an IP
mefctl bans delete <ip>       # Unban an IP
mefctl bans clear             # Clear all bans
```

### System Status
```bash
mefctl status                 # Show firewall status, ban sets, element counts
```

## Config
- Global config: `/etc/mef/mef.conf`
- Per-service rules: `/etc/mef/rules.d/*.conf`

Repo default config template: [conf/mef.conf](conf/mef.conf)

Global config (INI-style):
- `rules_dir` (default `/etc/mef/rules.d`)
- `whitelist_dir` (default `/etc/mef/whitelist`)
- `whitelist_reload` (default `1m`, supports `10s`, `1m`, or integer seconds)
- `blacklist_dir` (default `/etc/mef/blacklist`)
- `blacklist_reload` (default `1m`, supports `10s`, `1m`, or integer seconds)
- `cache_dir` (default `/etc/mef/cache`, daemon runtime state)
- `debug` (enable debug logging, default `false`)
- `debug_log` (log file path when debug is enabled, default `/tmp/mef.txt`)
- `ban_log_enabled` (enable dedicated BAN audit log, default `false`)
- `ban_log_path` (BAN audit log path, default `/var/log/mef.log`)
- `clear_bans_on_stop` (flush active ban sets when daemon stops, default `false`)
- `journal_since` (default `2 min ago`)
- `file_recent_limit` (startup cap for `source=file` matched logs, default `200`, `0` = disabled)
- `file_recent_window` (startup recency window for `source=file`, default `24h`, `0` = disabled)
- `firewall_backend` (`auto` | `nftables` | `iptables`)
- `firewall_family` (nftables table family, default `inet`)
- `firewall_table` (nftables table name, default `mef`)
- `firewall_chain` (nftables chain name / iptables chain, default `mef`)
- `firewall_hook` (nftables hook, default `input`)
- `firewall_priority` (nftables hook priority, default `-100`)
- `firewall_log_enabled` (enable LOG before DROP, default `true`)
- `firewall_log_prefix` (LOG prefix, default `MEF_`)
- `firewall_log_level` (LOG level, default `warn`)

## Whitelist
Whitelist files are read from `/etc/mef/whitelist/*.conf` (configurable via `whitelist_dir`).

Repo example whitelist: [conf/whitelist/example.conf](conf/whitelist/example.conf)

Format: one entry per line. Supported forms:
- `IP`
- `CIDR`
- `IP/MASK`

Comments are allowed:
- Full line comments with `#` or `;`
- Inline comments, e.g. `1.2.3.4 # office`

Whitelist entries are loaded into memory and reloaded periodically (default `1m`, configurable via `whitelist_reload`).

## Blacklist
Blacklist files are read from `/etc/mef/blacklist/*.conf` (configurable via `blacklist_dir`).

Repo example blacklist: [conf/blacklist/example.conf](conf/blacklist/example.conf)

Format: one entry per line (`IP` or `CIDR`).

Blacklist entries are enforced as permanent bans and reloaded periodically (default `1m`, configurable via `blacklist_reload`).

Whitelist has precedence: if an address matches both, whitelist wins.

## Firewall backends
- nftables (preferred)
- iptables (fallback)

### mefctl iptables notes
- Uses iptables/ip6tables; IPv6 rules require `ip6tables` in PATH.
- Address `set` references require `ipset` to be installed.
- Multiple negated interfaces in one `iif`/`oif` list are not supported by iptables (e.g. `!lo,!docker0`).

## Rule action (per-service)
Rules can specify action and ports:
- `action=ban` or `action=detect`
- `ports=all` or `ports=22,25` or `ports=22-2222`
- `backend=auto|nftables|iptables`

Optional escalation keys (fail2ban recidive style):
- `escalation_enabled=true|false`
- `escalation_window=24h` (Go duration or integer seconds)
- `permanent_threshold=5` (number of first-level bans before permanent ban)

Example: enable escalation only for nginx (`/etc/mef/rules.d/nginx.conf`):
```ini
escalation_enabled=true
escalation_window=24h
permanent_threshold=5
```

Keep other service rules with `escalation_enabled=false`.

## Code documentation
Keeping the code well-documented is important for this project. Please add clear file headers and comments for non-obvious logic so future maintenance and search are easy.

## Keywords

linux firewall, nftables, iptables, fail2ban alternative, intrusion prevention,
ip blocking, log monitoring, ssh protection, postfix protection,
systemd firewall service, freebsd firewall daemon
