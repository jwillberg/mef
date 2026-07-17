# mef

**mef (Malware.Expert Firewall)** is a lightweight Linux firewall and multi-layer automatic IP ban engine.

It combines:
- **Persistent firewall management** (nftables preferred, iptables fallback)
- **Fail2ban-style log monitoring and automatic IP blocking**
- Built-in **DDoS/FLOOD guard** (Stage 1 kernel `THROTTLE`, Stage 2 optional runtime `BAN`)
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
- **Two-stage DDoS/FLOOD protection** (`THROTTLE` in kernel, optional escalation to runtime `BAN`)
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
- Built-in **DDoS/FLOOD guard** (`THROTTLE` episodes from kernel set + optional Stage 2 runtime `BAN`)
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

`Two-stage DDoS guard (ddos_*)`
- nftables: Yes
- iptables: Yes (requires ipset/SET target support)
- Notes: Stage 2 escalation source is kernel throttle set state (not firewall log parsing).

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
- `ddos_enabled=true`
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
- `ddos_enabled=true` (requires ipset + SET target)
- Result: core mef features work, fastpath is not active.

`D) Minimal fallback`
- `firewall_backend=nftables` or `iptables`
- `ps_source_order=journal`
- `firewall_log_enabled=true`
- Result: PS/RBL fallback via firewall logs only.

Important behavior notes:
- `blacklist_fastpath=auto|xdp|tc` requires Linux + `firewall_backend=nftables`.
- `ps_packet_kernel_drop` only affects runtime when `packet` exists in `ps_source_order`.
- `ps_packet_rx_mode=recvfrom` is the default for stable legacy behavior; `auto` is available as opt-in.
- `ps_packet_fanout_sockets>1` applies only to `packet` source and opens multiple packet sockets per interface.
- `mefctl bans list --fastpath` works only with nftables backend on Linux.
- `ps_source_order` is shared by both PS and RBL/CLOUD source events.
- if `rbl_enabled=true`, changing only `ps_enabled=false` does not stop packet-source event collection.
- with `ps_source_order=conntrack` and `ps_exclude_ports=auto`, PS visibility can drop sharply because local listening service ports are auto-excluded from counting.
- `firewall_log_enabled=true` is rate-limited by `firewall_log_rate` / `firewall_log_burst` to prevent kernel/journal overload under flood.
- firewall LOG limits are applied per firewall LOG rule (not per source IP).

## v1.0.7 Stabilization Bug Notes (Symptoms, Root Cause, Fix)

Use this section when validating upgrades or incident cleanup.

`Symptom: high %si / ksoftirqd / journald load under flood when firewall logging is enabled`
- Root cause: firewall `LOG` rules were not rate-limited, so dropped packet floods could generate excessive kernel log volume.
- Fix: logging now uses token-bucket limits (`firewall_log_rate`, `firewall_log_burst`) in nftables and iptables paths; DROP remains unconditional.

`Symptom: DDOS stage event lines visible in daemon journal`
- Root cause: DDOS stage notices were written via daemon logger path.
- Fix: DDOS stage event notices are no longer emitted as daemon journal notice lines; event records stay in `ban_log` and optional `debug_log`.

`Symptom: DDOS BAN observability inconsistencies`
- Root cause: Stage 2 emitted `BAN` before apply success was guaranteed; stage1 throttle logging could continue for already runtime-banned IP.
- Fix: `BAN` is emitted only after successful apply; apply failures emit `BAN_FAIL`; duplicate stage1 `THROTTLE` for active runtime DDOS bans is suppressed.

`Symptom: mefctl pinned update version fails due metadata URL mismatch`
- Root cause: strict `updates.json` asset URL version segment validation blocked valid requested-version installs.
- Fix: mismatched metadata asset URL is treated as non-fatal and updater falls back to computed `vX.Y.Z` raw tag URL.

`Symptom: packet source high CPU under heavy PPS`
- Root cause: packet parser hot path parsed packet content twice and allocated event strings too early.
- Fix: single-pass parser path (PS-005) with deferred event/raw string build after blocked-source early check.

`Symptom: mmap packet source could amplify/unintentionally include outgoing frames on some kernels`
- Root cause: missing `PACKET_IGNORE_OUTGOING` support in certain kernel environments.
- Fix: mmap mode now fails/falls back in `auto` mode to prevent unsafe outgoing-frame behavior.

## Kernel Data Path Notes (Why Packet Source Still Sees Traffic)

When `ps_source_order` includes `packet`, mefdaemon reads traffic via Linux `AF_PACKET` raw socket.

- `packet` source receives a packet copy in userspace.
- Kernel firewall (`nft` / `iptables`) still enforces drop/accept in netfilter.
- Because of the socket copy path, packet source can still consume CPU under flood even when source IP is already banned.

Controls and behavior:

- `ps_packet_kernel_drop=true` (default): enables packet-source blocked-IP optimization path (kernel socket filter + early userspace skip).
- `ps_packet_kernel_drop=false`: packet source runs without blocked-IP kernel-drop optimization.
- `ps_packet_rx_mode=auto|recvfrom|mmap` controls packet receive implementation:
  - `auto`: try PACKET_MMAP/TPACKET_V3 first, fallback to recvfrom
  - `mmap`: require ring path (startup fails if unsupported)
  - `recvfrom`: force classic recvfrom loop
- `ps_packet_fanout_sockets=1..64` controls packet socket parallelism per interface (`>1` enables PACKET_FANOUT hash split).
- `blacklist_fastpath` (`auto|xdp|tc|disabled`) is a separate ingress fastpath layer and independent from `ps_packet_kernel_drop`.

Practical guidance:

- Highest flood resilience: `firewall_backend=nftables`, keep `ps_packet_kernel_drop=true`, and enable fastpath (`blacklist_fastpath=auto`/`tc`).
- Lowest userspace PS CPU (with tradeoff in scan visibility): use `ps_source_order=conntrack,journal`.
- If packet CPU is high during DDOS tests, move `ps_source_order` away from `packet` (for example `conntrack,journal`) or disable RBL/CLOUD while testing pure DDOS stage behavior.
- If you use `conntrack` source and need stronger PS detection, avoid broad `ps_exclude_ports=auto`; use tighter manual excludes.

## DDoS Guard (Kernel Set Source)

`ddos_enabled=true` activates two-stage protection:

1. Stage 1 (kernel soft throttle):
- backend-native per-port limits (`syn_rate`, `newconn_rate`, `connlimit`)
- mode is controlled by `ddos_stage1_mode`:
  - `throttle`: only over-limit packets/connections are dropped
  - `drop`: once source enters throttle set, all traffic from that source is dropped until `ddos_stage1_timeout`
- source IP is written into throttle kernel set on limit hit
- daemon emits `THROTTLE` log events for new throttle episodes (`RULE=DDOS`, `SOURCE=KERNEL`)
- DDOS event records are written to `ban_log` (default `/var/log/mef.log`) and optional `debug_log`; they are not emitted as daemon journal notice lines
- `THROTTLE`/`BAN` `msg` includes active Stage 1 trigger details when available:
  - protected destination port (`<metric>@<port>`)
  - exceeded limit family (`syn`, `newconn`, `connlimit`)
  - configured threshold values (`ddos_syn_rate`, `ddos_syn_burst`, `ddos_newconn_rate`, `ddos_newconn_burst`, `ddos_connlimit`)
- `throttle_hits` is an episode counter (`hit_model=episodes`), not raw packet count:
  - increments when source re-enters Stage 1 state (set transition absent -> present)
  - does not increment for every over-limit packet while source stays continuously in throttle set

2. Stage 2 (daemon hard-ban):
- daemon polls throttle kernel sets (IPv4/IPv6)
- poll cadence is controlled by `ddos_poll_interval` (default `5s`)
- controlled by `ddos_escalation_enabled`:
  - `true`: Stage 2 runtime DDOS bans are allowed
  - `false`: throttle/drop only mode (no DDOS runtime bans)
- repeated throttle episodes within `ddos_escalation_window` escalate to normal runtime ban flow (`RULE=DDOS`, `SOURCE=KERNEL`)
- `BAN` is logged only after runtime ban apply succeeds
- apply failures are logged as `BAN_FAIL` (`RULE=DDOS`, `SOURCE=KERNEL`)
- while DDOS runtime ban is active, new `THROTTLE` logs for that same IP are suppressed
- when `community_report=true`, only successful DDOS `BAN` events are reported (`service=ddos`)
- DDOS `THROTTLE` / `BAN_FAIL` events are local-only and never community-reported
- detail trigger context collection is controlled by `ddos_signal_details_enabled`:
  - `true` (default): includes metric+port trigger context in DDOS `msg`
  - `false`: skips detail-set writes/reads to lower overhead, logs show `signals=disabled`

Recommended enable pattern:
- keep `ddos_enabled=false` until tuned for your traffic profile
- protect only publicly exposed ports
- default baseline is `ddos_ports=80,443`
- add ports like `22,25,465,587` only when those services are internet-facing

Config keys:
- `ddos_ports`
- `ddos_syn_rate`, `ddos_syn_burst`
- `ddos_newconn_rate`, `ddos_newconn_burst`
- `ddos_connlimit`
- `ddos_stage1_mode`
- `ddos_stage1_timeout`
- `ddos_poll_interval`
- `ddos_signal_details_enabled`
- `ddos_escalation_enabled`
- `ddos_escalation_window`, `ddos_escalation_hits`, `ddos_bantime`
- optional per-port overrides: `ddos_port_<port>_*`

Units and scope:
- `ddos_syn_rate`: per second (1/s), per source IP, per protected destination port
- `ddos_newconn_rate`: per second (1/s), per source IP, per protected destination port
- `ddos_syn_burst`, `ddos_newconn_burst`: burst allowance count (no time unit)
- `ddos_connlimit`: concurrent connection count per source IP (no time unit)
- `ddos_stage1_mode`: Stage 1 action (`throttle` = drop only over-limit traffic, `drop` = temporary full drop while in throttle set)
- `ddos_stage1_timeout`: Stage 1 throttle-set timeout duration
- `ddos_poll_interval`: Stage 2 kernel-set poll interval (`5s` default; higher lowers CPU overhead)
- `ddos_signal_details_enabled`: enable/disable per-hit detail-set context (`false` reduces overhead, DDOS stays active)
- `ddos_escalation_enabled`: Stage 2 toggle (`true` = escalate to DDOS runtime ban, `false` = throttle/drop only)
- `ddos_escalation_window`: duration (for example `10m`, `1h`)
- `ddos_escalation_hits`: number of throttle episodes within `ddos_escalation_window`
- `ddos_bantime`: Stage 2 ban duration, or `permanent` for persistent blacklist ban

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
sudo ./update.sh --version 1.0.10 --force
```

### Download & extract (example)
```bash
# Replace URL/version as needed
curl -L -o /tmp/mef-release.tar.gz https://github.com/jwillberg/mef/archive/refs/tags/v1.0.10.tar.gz
mkdir -p /tmp/mef-release
tar -xzf /tmp/mef-release.tar.gz -C /tmp/mef-release --strip-components=1
cd /tmp/mef-release
```

### Manual install
#### Linux (systemd, Debian/Ubuntu/RHEL/Fedora)
```bash
case "$(uname -m)" in
  x86_64|amd64) MEF_ARCH=amd64 ;;
  aarch64|arm64) MEF_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
sudo mkdir -p /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist /etc/mef/cache
sudo cp -f "bin/mefdaemon_linux_${MEF_ARCH}" /usr/local/sbin/mefdaemon
sudo cp -f "bin/mefctl_linux_${MEF_ARCH}" /usr/local/sbin/mefctl
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
case "$(uname -m)" in
  x86_64|amd64) MEF_ARCH=amd64 ;;
  aarch64|arm64) MEF_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
sudo install -d /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist /etc/mef/blacklist /etc/mef/cache
sudo install -m 0755 "bin/mefdaemon_freebsd_${MEF_ARCH}" /usr/local/sbin/mefdaemon
sudo install -m 0755 "bin/mefctl_freebsd_${MEF_ARCH}" /usr/local/sbin/mefctl
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
mefctl version                         # Print version and exit (aliases: --version, -v)
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
                                 # Use --ddos for kernel DDoS throttle sets, --fastpath for fastpath sets
  add <IP[/CIDR]>                # Add manual ban (runtime by default)
  delete <IP[/CIDR]>             # Delete ban (runtime by default)
  clear                          # Clear runtime timeout ban sets (supports --ddos/--all)

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
mefctl update check                          # Check availability; do not install (no root required)
mefctl update [--force] [--version X.Y.Z]  # Install release binaries to /usr/local/sbin
```

### mefdaemon version

The daemon binary exposes the same lightweight version check. It exits before reading configuration, checking for updates, opening logs, or starting detector workers:

```bash
mefdaemon version
mefdaemon --version
mefdaemon -v
```

Notes:
- `[FILE]` is optional. If omitted, mefctl uses `/etc/mef/mef.rules`.
- `rules fmt` does NOT modify firewall state.
- `rules validate` is recommended before `rules apply`.
- `rules apply` auto-rolls back after `--timeout` if no `yes` confirmation is received.
- `rules apply` now verifies rollback restore results; if restore fails, it attempts backend clear fallback and reports rollback errors.
- manual `rules apply` does not activate boot lifecycle by itself; if `mef.service` is inactive/disabled, `stop mef` may not clear those manually-loaded rules and rules may not load on reboot.
- for managed lifecycle/persistence use: `mefctl enable mef && mefctl start mef` (manual cleanup remains `mefctl rules clear`).
- `rules migrate` reads running nftables rules and prints mef.rules text to stdout by default.
- `rules migrate` excludes the mef.conf managed nft table by default.
- `bans add --permanent` writes to `blacklist_dir/*.conf` and survives reboot.
- `bans add --permanent` rejects entries that overlap whitelist CIDRs.
- `bans delete` removes runtime + DDoS throttle sets by default.
- `bans delete --permanent` removes only permanent sets and `blacklist_dir/*.conf`.
- `bans delete --ddos` removes only DDoS throttle sets (`mefddos_throttle_v4/v6`).
- `bans delete --all` removes runtime + DDoS throttle + permanent sets and `blacklist_dir/*.conf`.
- `bans clear --ddos` clears only DDoS throttle sets.
- `bans clear --all` clears runtime + DDoS throttle sets.
- `bans list` (default) groups output to `Runtime`, `DDoS Throttle`, `Permanent`, `Per-Rule`, and `Other` sections.
- `bans list --permanent` shows only permanent sets.
- `bans list --ddos` shows only DDoS throttle sets.
- `bans list --all` explicitly selects the default "all sets" mode.
- `bans list --fastpath` shows kernel fastpath sets only (`netdev mef_fastpath`).
- `bans list` and `bans list --permanent` include permanent entries from `blacklist_dir/*.conf` even when fastpath is active.
- `bans list --fastpath` requires Linux + `nftables` backend (not available with `iptables` backend).
- `bans list --ips-only` prints only unique IP/CIDR values.
- `bans list --verbose` prints raw backend rows with source set.
- `config check` audits `[global]` keys and reports missing known keys (defaults in effect) plus unknown keys (possible typo/legacy).
- `config check` does not require hidden optional keys (`community_report_token`, `community_report_insecure_tls`) and does not warn when they are omitted.
- `--permanent`, `--ddos`, and `--all` are mutually exclusive scope selectors in `bans list` and `bans delete`.
- `status --verbose fastpath` prints fastpath lifecycle/debug details (`kernel_table`, source-of-truth, restart/crash behavior, management hints).
- `update` fetches release metadata from `updates.json` and installs `/usr/local/sbin/mefdaemon` and `/usr/local/sbin/mefctl`.
- `update check` fetches release metadata and prints the current, latest, and minimum supported versions without downloading, installing, restarting services, or requiring root privileges.
- Normal `mefctl` commands do not perform hidden network checks; use `mefctl update check` when a fresh availability result is wanted.
- Binary download prefers `updates.json` platform asset URLs (raw tag paths) and falls back to raw tag/main URLs (`github.com/.../raw/refs/tags/vX.Y.Z/bin/...`, `github.com/.../raw/refs/heads/main/bin/...`) when needed.
- If metadata asset URL version does not match requested `--version`, updater ignores that metadata URL and uses computed `vX.Y.Z` raw tag URLs.
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
  --ddos
  --all

bans list
  --permanent
  --ddos
  --all
  --fastpath
  --ips-only
  --verbose

bans clear
  --ddos
  --all

config check
  [FILE]                         # default /etc/mef/mef.conf

status
  --verbose
  fastpath

update
  check
  --force
  --version <X.Y.Z>
```

### systemctl/service management
```bash
# systemd (Linux)
systemctl status mef mefdaemon
systemctl reload mef          # Reload firewall rules
systemctl reload mefdaemon    # Reload daemon config and rules.d watchers

# FreeBSD
service mef status
service mefdaemon status
service mef reload            # Reload firewall rules
service mefdaemon reload      # Reload daemon config and rules.d watchers
```

`mefctl enable mefdaemon` note:
- prints PS prerequisite output only when attention is needed (warnings).
- when PS prerequisites are OK, it stays quiet (no extra `PSD: ... ready` line).

## Config
- Global config: `/etc/mef/mef.conf`
- Per-service rules: `/etc/mef/rules.d/*.conf`
- Startup behavior: mefdaemon now starts even when `rules.d` has no enabled rules (or no rule files). In that mode, only global detectors/features (PS, RBL, CLOUD) run if enabled.

Rule note (`source=journal`):
- `programs` supports exact names and wildcards, e.g. `sshd`, `sshd*`, `postfix/*`, or `*`.
- Use `mefctl reload mefdaemon` after adding, editing, enabling, disabling, or removing `rules.d/*.conf` files. The daemon validates the complete new rule set before replacing active journal/file watchers; if validation fails, the existing watchers remain active and the error is logged.
- After a binary upgrade, use `mefctl restart mefdaemon`.

The shipped disabled `nginx.conf` and `apache.conf` examples include a PHP-probe matcher for `.php` request paths, with optional query strings, returning HTTP `403`, `404`, or `406`. Each profile also includes a general HTTP error matcher. All matcher hits within one profile share that rule's `findtime`/`maxretry` counter. Both profiles exclude common static image, CSS, JavaScript/source-map, and web-font requests (case-insensitive, optional query string) so missing assets do not increase the ban counter. The Apache profile monitors common Debian/Ubuntu (`/var/log/apache2`) and RHEL-family (`/var/log/httpd`) access-log paths and accepts the optional `vhost:port` prefix used by `other_vhosts_access.log`.

Three disabled Exim examples are shipped for different installations: `exim-cpanel.conf`, `exim-directadmin.conf`, and the conservative generic fallback `exim.conf`. Enable only the profile matching the server. The cPanel and DirectAdmin profiles recognize their platform-specific SMTP AUTH `535 Incorrect authentication data` and invalid-HELO formats, plus connections dropped for excessive SMTP protocol errors. The generic profile recognizes only `535` SMTP AUTH failures and dropped protocol-abuse connections. These profiles deliberately exclude temporary `435` authentication failures, cancelled `501` authentication attempts, and broad `rejected RCPT` matching, because those records can represent delivery policy or ordinary recipient errors rather than an attack. All three profiles ban only SMTP ports `25`, `465`, and `587`; IMAP/POP authentication belongs in a separate Dovecot profile.

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
- `ps_packet_rx_mode` (packet receive path: `auto|recvfrom|mmap`, default `recvfrom`; `auto` tries PACKET_MMAP/TPACKET_V3 first and falls back to `recvfrom`)
- `ps_packet_fanout_sockets` (packet sockets per interface, default `1`, valid `1..64`; values `>1` enable PACKET_FANOUT hash distribution)
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
- `firewall_log_rate` (LOG rate limit in logs/second, default `1`; scope is per firewall LOG rule, not per source IP)
- `firewall_log_burst` (LOG burst bucket size, default `5`)

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
- `packet` parser path is single-pass in the reader loop (key + event from one decode), reducing per-packet userspace parse overhead versus older double-parse behavior.
- `packet` receive path can run in PACKET_MMAP ring mode (`ps_packet_rx_mode=auto|mmap`) with optional multi-socket fanout (`ps_packet_fanout_sockets>1`) for higher PPS workloads.
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
ps_packet_rx_mode=recvfrom
ps_packet_fanout_sockets=1
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
- `mefctl reload mefdaemon` reloads global config and the complete `rules.d` watcher set; use `restart` after binary upgrades.
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
- List active DDoS throttle entries:
  - `mefctl bans list --ddos`
  - `mefctl bans list --ddos --ips-only`
- Remove DDoS throttle entry only:
  - `mefctl bans delete <ip> --ddos`
- Clear DDoS throttle sets:
  - `mefctl bans clear --ddos`
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
- Service identifier (e.g. ssh, nginx, postfix, portscan, ddos, rbl, cloud)
- Timestamp (last seen)
- Pseudonymous reporter identifier (one-way hash)
- Structured rule metadata (`details` JSON object; fields vary by detection type)
  - `RBL` / `CLOUD`: `zone`, `answer`, `dport` (if available)
  - `PORTSCAN`: `ports`, `interval`, `limit`
  - Other services (e.g. `SSHD`): omitted when no structured details are available
- Service normalization: all non-cloud RBL profiles use `service=rbl` (not `rbl_<key>`); cloud uses `service=cloud`.
- DDOS reporting scope: only successful `BAN` events are reported (`service=ddos`); `THROTTLE` is not reported.

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
