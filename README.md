# mef

**mef (Malware.Expert Firewall)** is a lightweight Linux firewall and multi-layer automatic IP ban engine.

It combines:
- **Persistent firewall management** (nftables preferred, iptables fallback)
- **Fail2ban-style log monitoring and automatic IP blocking**
- **DNS-based RBL/DNSBL enforcement**
- Optional **Community Cloud threat intelligence**
- Built-in **Port Scan Detection (PS)**
- Native **systemd / FreeBSD service integration**

Designed as a simple, modern alternative to UFW, CSF and Fail2Ban stacks, with additional DNS and community-driven protection layers.

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
- Built-in **Port Scan Detection (PS)** with packet/conntrack/journal sources
- **RBL/DNSBL profiles** with port-scoped bans
- **Configurable RBL cache TTLs** (`positive_ttl`, `negative_ttl`, `error_ttl`)
- Optional **Community Cloud protection** (`community_cloud_protection`)
- Safe defaults, easy install

## Architecture

mef is split into two independent components:

- **mef** → firewall rules loader (persistent policy service)
- **mefdaemon** → log parser + dynamic IP ban engine

Firewall backends:
- nftables (primary)
- iptables (fallback)

The daemon maintains in-memory IP sets and updates firewall rules dynamically.

## Backend Feature Matrix (nftables vs iptables)

`Runtime timeout bans (mefbanned_*)`
- nftables: Yes
- iptables: Yes
- Notes: Both are kernel-enforced.

`Permanent blacklist sync (/etc/mef/blacklist/*.conf)`
- nftables: Yes
- iptables: Yes
- Notes: Same source-of-truth files, different backend implementation.

`Per-rule dynamic ban sets (banned_<rule>_*)`
- nftables: Yes
- iptables: Yes
- Notes: Created on demand when rules trigger.

`Fastpath (blacklist_fastpath)`
- nftables: Yes (Linux, nft `netdev` table)
- iptables: No
- Notes: Requires `firewall_backend=nftables`.

`mefctl bans list --fastpath`
- nftables: Yes
- iptables: No
- Notes: Command is nft-only.

`source=ipset:<name> in mef.rules`
- nftables: No
- iptables: Yes
- Notes: Native nft backend does not support external ipset source references.

`mefctl rules clear --all`
- nftables: Yes
- iptables: No
- Notes: `--all` is nft-table destructive clear.

`mefctl rules migrate`
- nftables: Yes
- iptables: Limited
- Notes: Current migrate flow targets nft rulesets.

Notes:
- On many modern distros, `iptables` may run in `iptables-nft` compat mode. That is still treated as `iptables` backend behavior in mef.
- For new distro targets, prefer `firewall_backend=nftables`; keep `iptables` as compatibility fallback.

## Valid Configuration Combinations (Quick Reference)

Use these as known-good combinations:

`A) Full feature set (recommended)`
- `firewall_backend=nftables`
- `ps_source_order=packet,conntrack,journal`
- `ps_packet_kernel_drop=true`
- `blacklist_fastpath=auto` (or `tc` / `xdp`)
- Result: packet visibility + blocked-IP optimization + optional ingress fastpath.

`B) Lower PS CPU usage`
- `firewall_backend=nftables`
- `ps_source_order=conntrack,journal`
- `blacklist_fastpath=auto` (optional)
- Result: lighter userspace path, but less scan visibility than `packet`.

`C) Compatibility mode`
- `firewall_backend=iptables`
- `ps_source_order=packet,conntrack,journal` (or subset)
- `blacklist_fastpath=disabled` (effective behavior on iptables backend)
- Result: core mef features work, fastpath is not active.

`D) Minimal fallback`
- `firewall_backend=nftables` or `iptables`
- `ps_source_order=journal`
- `firewall_log_enabled=true`
- Result: PS/RBL fallback via firewall logs only.

Important behavior notes:
- `blacklist_fastpath=auto|xdp|tc` requires Linux + `firewall_backend=nftables`.
- `ps_packet_kernel_drop` only affects runtime when `packet` exists in `ps_source_order`.
- `mefctl bans list --fastpath` works only with nftables backend on Linux.

## Kernel Data Path Notes (Why Packet Source Still Sees Traffic)

When `ps_source_order` includes `packet`, mefdaemon reads traffic via Linux `AF_PACKET` raw socket.

- `packet` source receives a packet copy in userspace.
- Kernel firewall (`nft` / `iptables`) still enforces drop/accept in netfilter.
- Because of the socket copy path, packet source can still consume CPU under flood even when source IP is already banned.

Controls and behavior:

- `ps_packet_kernel_drop=true` (default): enables packet-source blocked-IP optimization path (kernel socket filter + early userspace skip).
- `ps_packet_kernel_drop=false`: packet source runs without blocked-IP kernel-drop optimization.
- `blacklist_fastpath` (`auto|xdp|tc|disabled`) is a separate ingress fastpath layer and independent from `ps_packet_kernel_drop`.

Practical guidance:

- Highest flood resilience: `firewall_backend=nftables`, keep `ps_packet_kernel_drop=true`, and enable fastpath (`blacklist_fastpath=auto`/`tc`).
- Lowest userspace PS CPU (with tradeoff in scan visibility): use `ps_source_order=conntrack,journal`.

## Install

⚠️ **IMPORTANT:** Both services are **disabled by default** to prevent accidental lockout. You must enable them manually after testing.

### Quick install (after extract)
```bash
cd /tmp/mef-release
chmod +x install.sh update.sh uninstall.sh
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

Legacy update script (for older installs without `mefctl update`):
```bash
sudo ./update.sh
sudo ./update.sh --force
sudo ./update.sh --version 1.0.6 --force
```

### Download & extract (example)
```bash
# Replace URL/version as needed
curl -L -o /tmp/mef-release.tar.gz https://github.com/jwillberg/mef/archive/refs/tags/v1.0.6.tar.gz
mkdir -p /tmp/mef-release
tar -xzf /tmp/mef-release.tar.gz -C /tmp/mef-release --strip-components=1
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
                                 # Use --fastpath for kernel fastpath sets (nftables/Linux)
  add <IP[/CIDR]>                # Add manual ban (runtime by default)
  delete <IP[/CIDR]>             # Delete ban (runtime by default)
  clear                          # Clear runtime timeout ban sets (mefbanned_v4/v6)

mefctl lists <type>
  whitelist                      # Show whitelist entries
  blacklist                      # Show file-based permanent blacklist entries
  recidive                       # Show persistent recidive counters

mefctl config <action>
  check [FILE]                   # Audit mef.conf [global] keys (missing/unknown)

mefctl status [--verbose] [fastpath]
                                 # Show service + firewall status
                                 # fastpath target: fastpath-only lifecycle/debug view
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
- `bans add --permanent` rejects entries that overlap whitelist CIDRs.
- `bans delete` removes runtime ban sets only.
- `bans delete --permanent` removes only permanent sets and `blacklist_dir/*.conf`.
- `bans delete --all` removes runtime + permanent sets and `blacklist_dir/*.conf`.
- `bans list` (default) groups output to `Runtime`, `Permanent`, `Per-Rule`, and `Other` sections.
- `bans list --permanent` shows only permanent sets.
- `bans list --all` explicitly selects the default "all sets" mode.
- `bans list --fastpath` shows kernel fastpath sets only (`netdev mef_fastpath`).
- `bans list` and `bans list --permanent` include permanent entries from `blacklist_dir/*.conf` even when fastpath is active.
- `bans list --fastpath` requires Linux + `nftables` backend (not available with `iptables` backend).
- `bans list --ips-only` prints only unique IP/CIDR values.
- `bans list --verbose` prints raw backend rows with source set.
- `config check` audits `[global]` keys and reports missing known keys (defaults in effect) plus unknown keys (possible typo/legacy).
- `--permanent` and `--all` are mutually exclusive.
- `status --verbose fastpath` prints fastpath lifecycle/debug details (`kernel_table`, source-of-truth, restart/crash behavior, management hints).
- `update` fetches release metadata from `updates.json` and installs `/usr/local/sbin/mefdaemon` and `/usr/local/sbin/mefctl`.
- Binary download prefers `updates.json` platform asset URLs (raw tag paths) and falls back to raw tag/main URLs (`github.com/.../raw/refs/tags/vX.Y.Z/bin/...`, `github.com/.../raw/refs/heads/main/bin/...`) when needed.
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
  --all

bans list
  --permanent
  --all
  --fastpath
  --ips-only
  --verbose

config check
  [FILE]                         # default /etc/mef/mef.conf

status
  --verbose
  fastpath

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
- Startup behavior: mefdaemon now starts even when `rules.d` has no enabled rules (or no rule files). In that mode, only global detectors/features (PS, RBL, CLOUD) run if enabled.

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
- `blacklist_fastpath` (Linux permanent-blacklist acceleration: `auto|xdp|tc|disabled`, default `auto`; `auto` prefers XDP and falls back to `tc`)
- `blacklist_fastpath_xdp_mode` (XDP attach preference: `auto|native|generic`, default `auto`)
- `cache_dir` (default `/etc/mef/cache`, daemon runtime state)
- `debug` (enable debug logging, default `false`)
- `debug_log` (log file path when debug is enabled, default `/tmp/mef.txt`)
- `ban_log_enabled` (enable dedicated BAN audit log, default `false`)
- `ban_log_path` (BAN audit log path, default `/var/log/mef.log`)
- `community_report` (optional community reporting for structured ban indicators, default `false`; startup logs `community reporting disabled/enabled`; enabled mode logs batch interval + short server ID; delivery is best-effort/non-blocking, includes transient retry attempts, and does not affect local bans)
- `community_cloud_protection` (optional cloud DNS protection, default `false`; requires `community_report=true`; emits `RULE=CLOUD | SOURCE=DNS` bans)
- `community_cloud_ports` (cloud DNS protection port scope: `all`, `22,443`, `100-2000`; default `all`)
- `community_cloud_bantime` (cloud DNS protection ban duration, default `1h`)
- `community_cloud_timeout` (cloud DNS lookup timeout, default `2s`)
- `community_cloud_positive_ttl` (cloud DNS cache TTL for listed results, default `1h`)
- `community_cloud_negative_ttl` (cloud DNS cache TTL for not-listed results, default `15m`)
- `community_cloud_error_ttl` (cloud DNS cache TTL for lookup errors/timeouts, default `30s`)
- `rbl_enabled` (enable optional DNSBL checks, default `false`)
- `rbl_<key>_enabled` (enable profile, key uses `[a-z0-9]+`)
- `rbl_<key>_zone` (DNSBL zone, default profile uses `bl.blocklist.de`)
- `rbl_<key>_answer_match` (response IP glob list, e.g. `127.0.0.*,127.*,*`)
- `rbl_<key>_ports` (port scope: `all`, `22,443`, `100-2000`)
- `rbl_<key>_bantime` (RBL ban duration)
- `rbl_<key>_timeout` (DNS lookup timeout)
- `rbl_<key>_positive_ttl` (cache TTL for listed results)
- `rbl_<key>_negative_ttl` (cache TTL for not-listed results)
- `rbl_<key>_error_ttl` (cache TTL for lookup errors/timeouts)
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
- `ps_packet_udp` (include UDP in `packet` source tracking, default `false`; when `true`, mefdaemon auto-manages `/etc/mef/whitelist/auto-whitelist.conf` with DNS resolvers, default gateways, and DHCP server IPs to reduce false positives)
- `ps_packet_kernel_drop` (enable packet-source blocked-IP kernel-drop/early-skip path, default `true`; independent from `blacklist_fastpath`, set `false` to run packet source without this optimization)
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
- `packet` source uses kernel-level cBPF prefiltering and (when `ps_interface` is not `all`) binds sockets to resolved interface set; filter/socket set is reloaded automatically when `ps_interface` or auto `ps_exclude_ports` resolution changes.
- Fallback: `conntrack`
- Last fallback: `journal` (requires firewall logging and matching prefix)

Source behavior differences:
- `packet` sees raw inbound packets early and catches scans against dropped/closed ports, but can use more CPU under heavy flood traffic.
- `packet` reader can use blocked-IP early skip path (minimal parse + snapshot lookup) when `ps_packet_kernel_drop=true`, avoiding full event/channel/tracker work for already blocked sources.
- `conntrack` is lighter but only sees flows that reach conntrack `NEW` tracking; scans against dropped/non-tracked ports may be invisible.
- With `ps_exclude_ports=auto`, local listening service ports (for example `22,25,80,443,465,587`) are excluded from PS counting for all sources.
- PS ban threshold is strict: ban triggers when `unique_ports > ps_limit` (not `>=`).

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
ps_packet_kernel_drop=true
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
- `[PORTSCAN] ... HIT ... unique_ports=X/Y` (only when a new unique destination port is observed)
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
- Stats include `repeat_port` for repeated same-port events that do not increase `unique_ports`.
- Packet source stats include `skip_banned_early` for packets dropped in the reader before full event processing (`ps_packet_kernel_drop=true`).
- `ps_exclude_ports=auto` detects local listening server ports (TCP+UDP) and excludes them from PS counting.
- `ps_packet_udp=true` enables UDP tracking for `packet` source and auto-generates `/etc/mef/whitelist/auto-whitelist.conf` (resolvers, gateways, DHCP servers).
- If `ps_packet_udp` is disabled (or PS is disabled), that auto-generated whitelist file is removed.
- Specific bind IPs (including public IPs) are matched against `ps_interface`/`ps_interface_exclude`; `0.0.0.0`/`::` applies to tracked interfaces.

## RBL (DNSBL)

RBL is optional and can trigger from:
- PS source pipeline (`packet` / `conntrack` / `journal` firewall logs)
- `rules.d/*` rule hits (`source=journal` and `source=file`)

- Runs asynchronously (fail-open); lookup latency does not block local detection flow.
- Uses per-profile cache (`positive_ttl`, `negative_ttl`, `error_ttl`) and pending-query deduplication.
- Supports multiple profiles via dynamic keys: `rbl_<key>_*` (key: `[a-z0-9]+`).
- Supports port-scoped bans per profile via `rbl_<key>_ports`.
- PS source stack is Linux-only; `rules.d` trigger path works with normal rule sources (`file` / `journal`).
- Apply RBL config changes with `mefctl restart mefdaemon` (reload alone does not restart source workers).
- Malware.Expert cloud DNS profile is handled via `community_cloud_protection=true` (logged as `RULE=CLOUD`), not via `rbl_<key>_zone`.

Default profile (`blocklist`) in `/etc/mef/mef.conf`:
```ini
rbl_enabled=true
rbl_blocklist_enabled=true
rbl_blocklist_zone=bl.blocklist.de
rbl_blocklist_answer_match=127.0.0.*,127.*,*
rbl_blocklist_ports=all
rbl_blocklist_bantime=1h
rbl_blocklist_timeout=2s
rbl_blocklist_positive_ttl=1h
rbl_blocklist_negative_ttl=15m
rbl_blocklist_error_ttl=30s
```

Expected `mef.log` RBL BAN entry:
- `RULE=RBL | SOURCE=DNS | BAN | ip=1.2.3.4 | bantime=1h | action=ban | profile=blocklist | msg="zone=bl.blocklist.de answer=127.0.0.2 src=1.2.3.4 dport=22 proto=tcp dst=95.217.31.237 iface=eth0"` (trigger context fields are included when available)

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
- Reserved auto-managed file: `/etc/mef/whitelist/auto-whitelist.conf` (created only when `ps_enabled=true` and `ps_packet_udp=true`).

## Blacklist
Blacklist files are read from `/etc/mef/blacklist/*.conf` (configurable via `blacklist_dir`).

Repo example blacklist: [conf/blacklist/example.conf](conf/blacklist/example.conf)

Format: one entry per line (`IP` or `CIDR`).

Blacklist entries are enforced as permanent bans and reloaded periodically (default `1m`, configurable via `blacklist_reload`).

Set mapping:
- `auto-permanent.conf` -> `mefpermbanned_v4` / `mefpermbanned_v6`
- other `*.conf` files -> `mefbl_<filename>_v4` / `mefbl_<filename>_v6`

Reload behavior:
- reload is file-granular (only changed blacklist files are re-synced)
- small changes use add/delete diff updates
- large changes use atomic tmp+swap set sync with batched nft element loading

Whitelist has precedence: if an address matches both, whitelist wins.

## Fastpath operations (tc/xdp)

Fastpath is managed by `mefdaemon` from the same source-of-truth as permanent blacklist enforcement.
Active fastpath enforcement requires Linux with `nftables` backend (`iptables` backend keeps fastpath disabled).

Inspect:
```bash
mefctl status --verbose fastpath
mefctl bans list --fastpath --ips-only
```

Typical output fields:
- `active/configured mode` (`tc`, `xdp`, `disabled`)
- `ifaces`
- `entries_v4`, `entries_v6`
- `prefixes` (CIDR prefixes, non-host entries)
- `last_sync`

Lifecycle:
- `mefctl reload mefdaemon` or `mefctl restart mefdaemon` re-syncs fastpath state from blacklist files and runtime ban snapshots.
- If daemon crashes, `table netdev mef_fastpath` may remain in kernel until next daemon sync or manual delete.
- Runtime timeout ban mirror has short periodic sync lag (not strictly per-event instant).

Ban management through mefctl:
- List active kernel fastpath entries:
  - `mefctl bans list --fastpath`
  - `mefctl bans list --fastpath --ips-only`
- Remove runtime timeout bans:
  - `mefctl bans clear`
- Remove one permanent entry:
  - `mefctl bans delete <ip-or-cidr> --permanent`
- Remove one entry from everywhere:
  - `mefctl bans delete <ip-or-cidr> --all`

Emergency reset:
```bash
nft delete table netdev mef_fastpath
mefctl restart mefdaemon
```

Difference vs `inet mef`:
- `netdev mef_fastpath` (`tc` ingress) drops early before userspace packet parsing.
- `inet mef` contains normal firewall/runtime/per-rule enforcement path.

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

## Community Reporting (Optional)

mef includes an optional community reporting feature that can contribute structured security indicators to the Malware.Expert - Attack Intelligence database.

### Disabled by Default

Community reporting is **disabled by default**.
It must be explicitly enabled by the system administrator.

All firewall decisions and bans are always executed locally.
Enabling community reporting does not affect local ban logic.

Participation is voluntary and independent from core firewall functionality.
When enabled, reports are sent to a built-in cloud endpoint.

### Data Transmitted (When Enabled)

If enabled, the following structured data may be transmitted:

- Attacker IP address
- Service identifier (e.g. ssh, nginx, postfix, portscan, rbl, cloud)
- Timestamp (last seen)
- Pseudonymous reporter identifier (one-way hash)
- Structured rule metadata (`details` JSON object; fields vary by detection type)
  - `RBL` / `CLOUD`: `zone`, `answer`, `dport` (if available)
  - `PORTSCAN`: `ports`, `interval`, `limit`
  - Other services (e.g. `SSHD`): omitted when no structured details are available
- Service normalization: all non-cloud RBL profiles use `service=rbl` (not `rbl_<key>`); cloud uses `service=cloud`.

The reporter identifier is generated locally.
Malware.Expert receives only the hash value, never the underlying server identifier.

### Data NOT Transmitted

mef does NOT transmit:

- Raw log entries
- Usernames
- Authentication attempts
- Message contents
- Target server IP addresses
- Application payload data

### Purpose

Submitted data is used solely for:

- Aggregating malicious IP intelligence
- Improving automated threat detection
- Providing an IP reputation feed for legitimate security purposes

### Privacy & Legal

See:

- Privacy Notice: https://malware.expert/privacy-notice/
- Terms of Service: https://malware.expert/terms-of-service/

## Code documentation
Keeping the code well-documented is important for this project. Please add clear file headers and comments for non-obvious logic so future maintenance and search are easy.

## Keywords

linux firewall, nftables, iptables, fail2ban alternative, intrusion prevention,
ip blocking, log monitoring, ssh protection, postfix protection,
systemd firewall service, freebsd firewall daemon, csf

## Disclaimer

Threat intelligence data (if used) is provided "as is" without warranties of accuracy, completeness, or fitness for a particular purpose.
