# Release notes

## Unreleased

## v1.0.3 - 2026-02-21
- mefctl: harden `update` metadata fetch with retries and fallback URLs to reduce transient `updates.json` timeout failures (`Client.Timeout exceeded while awaiting headers`).
- mefctl: fix `update` binary download 404s by adding fallback to tag raw binary URLs (`github.com/.../raw/refs/tags/vX.Y.Z/bin/...`) and main-branch raw URLs when GitHub Release asset URL is missing.
- PS: when `ps_enabled=true` and `ps_packet_udp=true`, auto-manage `/etc/mef/whitelist/auto-whitelist.conf` using detected DNS resolvers, default-route gateways (IPv4/IPv6), and DHCP server IPs to reduce UDP false positives.
- mefctl: `update` now uses `updates.json` platform asset URL as primary binary source (instead of probing GitHub `releases/download` first), avoiding noisy 404 + fallback logs when release assets are not used.
- release: add `update.sh` legacy updater script for environments where `mefctl update` is unavailable; supports `--force` and pinned `--version`.
- mefdaemon: add optional `community_report=true/false` (default `false`) for batched JSON community reporting (60s interval) with fields `server_id` (`sha256(server_ip + hardware_id)`), `client_ip`, `service`, and `timestamp`; startup now logs `community reporting disabled/enabled`.
- mefdaemon: community reporting startup enabled log now shows batch interval + shortened `server_id`. Report delivery failures are silent and never affect local ban behavior.

## v1.0.2 - 2026-02-21
- PS: fix conntrack ENOBUFS event loss by passing `--buffer-size` to `conntrack -E` and adding configurable `ps_conntrack_buffer_size` (default 8388608 bytes).
- PS: add Linux `packet` source (`ps_source_order=packet,...`) to detect TCP `SYN && !ACK` directly from kernel raw packet socket without conntrack CLI or firewall log rules (requires `CAP_NET_RAW`).
- PS: packet-source debug/statistics: now logs all HIT/skip reasons (local, whitelist, banned), and prints 30s interval stats (events, tracked, skip_local, skip_whitelist, skip_banned, bans).
- PS: memory-pruning: portscan counters and skip/banned state are now automatically pruned, so no memory leak from idle IPs.
- PS: diagnostics: much easier to see why an IP is not banned (e.g. whitelisted, local, too few unique ports, etc).
- PS: normalize `RULE=PORTSCAN` BAN log format to match other rules (`bantime`, `action`, `msg`) and include PS details (`unique_ports`, `limit`, `interval`, `ports`) inside `msg`.
- PS: add `ps_interface` filter (`auto`, `eth0`, `eth0,eth1`) and `ps_interface_exclude` (`lo`, `lo,eth1`) to scope port-scan tracking per network interface; default exclude is now `lo` and `auto` resolves default-route interface(s).
- PS: add `ps_stats` (`true`/`false`, default `true`) to control periodic `port scan stats ...` logging.
- PS: add `ps_stats_interval` to configure periodic stats cadence (e.g. `30s`, `1m`, `5m`; default `30s`).
- PS: add `ps_exclude_ports` (`auto`, manual lists/ranges, or combined) plus `ps_exclude_ports_refresh`; auto mode detects listening TCP/UDP server ports and respects PS interface filters.
- PS: log effective excluded port list explicitly (`port scan excluded ports active=...`) and on auto refresh updates.
- PS: add `ps_packet_udp` (`true`/`false`, default `false`) to optionally include UDP in Linux `packet` source tracking (default behavior remains TCP `SYN && !ACK` only).
- mefctl: fix `bans delete <ip>` / `bans add <ip>` default port handling so implicit `all` no longer fails with `invalid port "all"`.
- mefctl: add `--permanent` mode for `bans add` (persist to blacklist files, survives reboot).
- mefctl: `bans delete` now removes runtime ban sets by default; `bans delete --permanent` additionally removes permanent sets and matching entries from `blacklist/*.conf`.
- mefctl: improve `bans list` UX (default grouped by `Runtime`/`Permanent`/`Per-Rule`/`Other`, `--ips-only` for plain unique IP/CIDR output, `--verbose` for raw rows).
- mefctl: add `update [--force] [--version X.Y.Z]` command to install release binaries to `/usr/local/sbin`; `--version` supports pinned installs/downgrades within `updates.json` bounds (`min_version..latest_version`) and downgrade requires `--force` (attempts to restart `mefdaemon` after update).

## v1.0.1 - 2026-02-20
- Fix journald program prefilter matching so rules like `programs=sshd` also match derived program names such as `sshd-session` (and similarly `postfix/smtpd` with `programs=postfix`) in `journal_mode=all`.
- Add wildcard support for journal program filters (`programs=sshd*`, `programs=postfix/*`) and fix `programs=*` handling so failregex compilation is not skipped.
- Add initial Linux Port Scan Detection (PS): counts unique destination ports per source IP (`ps_limit`/`ps_interval`) with temporary ban (`ps_bantime`) and optional permanent escalation (`ps_escalation_*`).
- Docs: add PS validation examples (`RULE=PORTSCAN` in `mef.log`, conntrack/source checks) to release README.

## v1.0.0 - 2026-01-29
- Initial public release
