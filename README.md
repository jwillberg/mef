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
curl -LO https://github.com/jwillberg/mef/releases/download/v1.0.2/mef-release.tar.gz
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
sudo install -d /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist
sudo install -m 0644 conf/rules.d/*.conf /etc/mef/rules.d/
sudo install -m 0644 conf/whitelist/example.conf /etc/mef/whitelist/example.conf
sudo install -m 0644 conf/blacklist/example.conf /etc/mef/blacklist/example.conf
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
```

## Commands

### mefctl (CLI)
```bash
mefctl rules <action> [FILE]     # default FILE: /etc/mef/mef.rules
  fmt                            # Normalize/pretty-print rules file
  validate                       # Validate syntax + interfaces (recommended before apply)
  apply                          # Apply rules to firewall
  clear                          # Remove mefctl rules
  migrate                        # Export running nftables table to mef.rules format
  clear --all                    # Delete whole nftables table (DANGEROUS)
  clear --all --force            # Skip confirmation

mefctl bans <action>
  list                           # List current bans grouped by category/set
  add <IP[/CIDR]>                # Add manual ban
  delete <IP[/CIDR]>             # Delete runtime ban (use --permanent for persistent removal)
  clear                          # Clear mefdaemon bans only

mefctl lists <type>
  whitelist                      # Show whitelist entries
  blacklist                      # Show permanent blacklist entries
  recidive                       # Show persistent recidive counters

mefctl status                    # Show service + firewall status
mefctl enable [mef|mefdaemon]
mefctl disable [mef|mefdaemon]
mefctl start   <mef|mefdaemon>
mefctl stop    <mef|mefdaemon>
mefctl reload  <mef|mefdaemon>
mefctl restart <mef|mefdaemon>
mefctl update [--force] [--version X.Y.Z]  # Install release binaries to /usr/local/sbin
```

Notes:
- `[FILE]` is optional. If omitted, mefctl uses `/etc/mef/mef.rules`.
- `rules fmt` does NOT modify firewall state.
- `rules validate` is recommended before `rules apply`.
- `rules migrate` reads running nftables rules and prints mef.rules text to stdout by default.
- `rules migrate` excludes the mef.conf managed nft table by default.
- `bans add --permanent` writes to `blacklist_dir/*.conf` and survives reboot.
- `bans delete` removes runtime ban sets only.
- `bans delete --permanent` also removes from permanent sets and `blacklist_dir/*.conf`.
- `bans list` (default) groups output to `Runtime`, `Permanent`, `Per-Rule`, and `Other` sections.
- `bans list --ips-only` prints only unique IP/CIDR values.
- `bans list --verbose` prints raw backend rows with source set.
- `update` fetches release metadata from `updates.json` and installs `/usr/local/sbin/mefdaemon` and `/usr/local/sbin/mefctl`.
- `update --version X.Y.Z` installs a specific version.
- Version pinning is bounded by metadata: `min_version <= X.Y.Z <= latest_version`.
- Downgrade requires `--force`.
- `update` requires root privileges.

### mefctl Options
```bash
rules fmt
  --write
  --out <FILE>

rules apply
  --timeout <duration>
  --yes

rules migrate
  --write                        # write to /etc/mef/rules.migrate
  --out <FILE>
  --family <ip|ip6|inet>
  --table <NAME>

bans add
  --timeout <duration>
  --ports <port[,port,...]>
  --permanent

bans delete
  --ports <port[,port,...]>
  --permanent

bans list
  --ips-only
  --verbose

update
  --force
  --version <X.Y.Z>
```

### systemctl/service management
```bash
# systemd (Linux)
systemctl status mef mefdaemon
systemctl reload mef          # Reload firewall rules
systemctl reload mefdaemon    # Reload daemon config

# FreeBSD
service mef status
service mefdaemon status
service mef reload            # Reload firewall rules
service mefdaemon reload      # Reload daemon config
```

## Config
- Global config: `/etc/mef/mef.conf`
- Per-service rules: `/etc/mef/rules.d/*.conf`

Rule note (`source=journal`):
- `programs` supports exact names and wildcards, e.g. `sshd`, `sshd*`, `postfix/*`, or `*`.
- Use `mefctl reload mefdaemon` for config changes only; after binary upgrade, use `mefctl restart mefdaemon`.

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
- `ps_enabled` (enable Port Scan Detection, Linux-only in current version)
- `ps_limit` (ban threshold for unique destination ports within interval)
- `ps_interval` (PS sliding window, Go duration or integer seconds)
- `ps_bantime` (PS temporary ban duration, Go duration or integer seconds)
- `ps_interface` (PS interface filter: `auto`, single interface like `eth0`, or CSV like `eth0,eth1`)
- `ps_interface_exclude` (PS interface exclude list, default `lo`; supports `lo` or `lo,eth1`)
- `ps_stats` (emit periodic PS stats logs while source is active, default `true`)
- `ps_stats_interval` (PS stats log interval, default `30s`; supports `30s`, `1m`, `5m` or integer seconds)
- `ps_exclude_ports` (exclude destination ports from PS counting; default `auto`: `auto`, manual `22,443,100-500`, or combined `auto,22,443`)
- `ps_exclude_ports_refresh` (refresh interval for `ps_exclude_ports=auto`, default `1m`)
- `ps_source_order` (source priority list, default `packet,conntrack,journal`)
- `ps_packet_udp` (include UDP in `packet` source tracking, default `false`; when `false`, packet source tracks only TCP `SYN && !ACK`)
- `ps_escalation_enabled` (enable PS second-stage permanent blacklist escalation)
- `ps_escalation_window` (PS escalation window)
- `ps_permanent_threshold` (first-stage PS bans before permanent blacklist)
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

## Port Scan Detection (PS)

PS is a global detector (not a per-service `rules.d` rule):
- Detects source IPs that hit many **different destination ports** in a short window.
- Intended for port scanning behavior (`ps_limit` + `ps_interval`).
- Not intended to replace service-specific brute-force detection on a single port (SSH/SMTP/HTTP), which still belongs in `rules.d` failregex rules.

Linux v1 source order (default):
- Primary: `packet` (raw socket, requires `CAP_NET_RAW`; default tracks TCP `SYN && !ACK`, optional UDP via `ps_packet_udp=true`)
- Fallback: `conntrack`
- Last fallback: `journal` (requires firewall logging and matching prefix)

Linux package prerequisite for `conntrack` source:
- Debian/Ubuntu: `apt install conntrack`
- RHEL/Rocky/Alma/Fedora: `dnf install conntrack-tools` (or `yum install conntrack-tools`)
- If not installed, PS can still run with `packet` source (if `CAP_NET_RAW` is available) or journal fallback (`firewall_log_enabled=true`).

Recommended test config (`/etc/mef/mef.conf`):
```ini
ps_enabled=true
ps_limit=10
ps_interval=300
ps_bantime=3600
ps_interface=auto
ps_interface_exclude=lo
ps_stats=true
ps_stats_interval=1m
ps_exclude_ports=auto,22,443
ps_exclude_ports_refresh=1m
ps_source_order=packet,conntrack,journal
ps_packet_udp=false
ps_escalation_enabled=true
ps_escalation_window=24h
ps_permanent_threshold=3
```

Apply and verify:
```bash
mefctl restart mefdaemon
journalctl -u mefdaemon -f
```

Expected runtime logs:
- `port scan source=packet active` (or `source=conntrack` / `source=journal` fallback)
- `port scan excluded ports active=22,25,53,80,443` (example)
- `[PORTSCAN] ... HIT ... unique_ports=X/Y`
- `[PORTSCAN] ... BAN ...` after threshold is exceeded
- Optional `[PORTSCAN] ... PERM_BAN ...` when escalation threshold is reached

Expected `mef.log` BAN entries (when `ban_log_enabled=true`):
- `RULE=PORTSCAN | SOURCE=PACKET | BAN | ip=... | bantime=1h | action=ban | msg="unique_ports=11 limit=10 interval=5m ports=22,25,80,443,..."`
- Optional escalation: `RULE=PORTSCAN | SOURCE=PACKET | PERM_BAN | ip=...`

Quick checks:
```bash
command -v conntrack
journalctl -u mefdaemon -n 100 --no-pager | grep -E "port scan source=|PORTSCAN"
grep "RULE=PORTSCAN" /var/log/mef.log
```

Firewall verification examples:
```bash
# nftables backend
nft list set inet mef mefbanned_v4
nft list set inet mef mefbanned_v6

# permanent blacklist set (if escalation triggered)
nft list set inet mef mefpermbanned_v4
nft list set inet mef mefpermbanned_v6
```

Notes:
- `mefctl reload mefdaemon` reloads config only; use `restart` after binary upgrades.
- Whitelist is always checked before PS counting/banning.
- FreeBSD currently runs PS as no-op (Linux-only in this version).
- `ps_interface=auto` selects default-route interface(s); explicit lists (`eth0,eth1`) restrict PS to those interfaces.
- `ps_interface_exclude` removes interfaces from tracking (default `lo`, so loopback is excluded by default).
- `ps_stats=false` disables periodic `port scan stats ...` log lines.
- `ps_stats_interval` controls stats frequency; counters are runtime-only and reset on daemon/source restart.
- `ps_exclude_ports=auto` detects local listening server ports (TCP+UDP) and excludes them from PS counting.
- `ps_packet_udp=true` enables UDP tracking for `packet` source; keep it `false` if you only want TCP SYN-based detection.
- Specific bind IPs (including public IPs) are matched against `ps_interface`/`ps_interface_exclude`; `0.0.0.0`/`::` applies to tracked interfaces.

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
