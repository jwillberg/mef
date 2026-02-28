# Release notes

## Unreleased

## v1.0.8 - 2026-02-28
- mefctl/rules apply: fix rollback reliability on confirm-timeout/no-confirm path.
- mefctl/rules apply: rollback now verifies restore result; if restore fails, it attempts backend clear fallback and reports failures instead of silently printing success.
- mefctl/rules apply: add post-apply lifecycle hint when `mef.service` is inactive/disabled, clarifying manual apply vs service-managed stop/boot behavior.
- mefctl/enable mefdaemon: PS prerequisite output is now warnings-only; when prerequisites are healthy it no longer prints extra `PSD: ... ready` line or blank spacer.

## v1.0.7 - 2026-02-27
- firewall/logging: add rate-limited firewall LOG controls to reduce softirq/journal overload under flood when `firewall_log_enabled=true`.
- firewall/logging: add `firewall_log_rate` (default `1`) and `firewall_log_burst` (default `5`) with conservative production defaults (`1/5`); DROP remains unconditional.
- mefctl/update: fix pinned-version install/downgrade path when `updates.json` asset URL points to a different tag; fallback to computed raw tag URL.
- ps/packet (PS-006): add high-PPS receive mode controls `ps_packet_rx_mode=auto|recvfrom|mmap` and `ps_packet_fanout_sockets=1..64`.
- ps/packet: add mmap-ring packet reader path (TPACKET_V3) with fallback/compatibility recvfrom path.
- ps/packet safety: keep default `ps_packet_rx_mode=recvfrom` (stable rollout); mmap/auto remain opt-in.
- ps/packet safety: if kernel lacks `PACKET_IGNORE_OUTGOING`, mmap mode now fails/falls back in auto mode to avoid outgoing-frame amplification.
- ps/packet (PS-005): implement single-pass parse path and keep early-drop-hit path allocation-light with deferred event string construction.
- tests/perf: add Linux packet parser benchmarks (`BenchmarkPacketReadEvent*`) and read-loop early-drop regression tests.
- ddos/cpu: optimize Stage 2 polling path so episode detection runs before detail-set reads and detail reads are scoped by episode IP family/set.
- config: add `ddos_poll_interval` (default `5s`) for Stage 2 poll cadence tuning.
- config: add `ddos_signal_details_enabled=true|false` (default `true`) for optional Stage 1 detail-set overhead control.
- mefdaemon/mefctl: extend config key-audit coverage for `ddos_poll_interval` and `ddos_signal_details_enabled`.
- docs: clarify PS/RBL source-order CPU behavior (`packet` visibility vs `conntrack` overhead tradeoff) and conntrack+auto-exclude PS visibility caveat.
- mefdaemon: add initial DDOS-001 reimplementation with two-stage DDoS guard (`ddos_*`):
  - Stage 1 kernel soft throttle rules per protected port (`syn_rate`, `newconn_rate`, `connlimit`) for nftables and iptables backends.
  - Stage 2 daemon escalation polls backend throttle kernel sets directly (not firewall log parsing) and escalates repeat offenders to runtime bans (`RULE=DDOS`, `SOURCE=KERNEL`).
- config: add DDOS global keys and per-port override syntax (`ddos_port_<port>_{syn_rate,syn_burst,newconn_rate,newconn_burst,connlimit}`) with parser validation.
- config defaults: change `ddos_ports` baseline default to `80,443` (from broad mixed-service list) to reduce accidental over-enforcement on non-exposed ports.
- mefdaemon: add DDOS whitelist-kernel-set sync (IPv4/IPv6) so whitelist entries bypass DDOS throttle/escalation path.
- mefdaemon/mefctl: extend `config check` key-audit coverage for DDOS keys (including dynamic per-port keys).
- tests/docs: add DDOS config + tracker unit tests, update release README/conf template, and improve `mef.conf` readability with clearer spacing between settings.
- docs: clarify DDOS key units/scope in `mef.conf` and README (`per-second` vs `burst count` vs `concurrent count`, plus escalation duration/count semantics).
- config: add `ddos_escalation_enabled=true|false` (default `true`) to choose Stage 2 DDOS runtime-ban escalation vs throttle/drop-only mode.
- config audit: fix hidden-key false positive; `community_report_insecure_tls` is now treated as hidden optional key (same as `community_report_token`) and is no longer reported missing when omitted.
- ddos observability: add Stage 1 throttle logging (`THROTTLE`) in addition to Stage 2 escalation ban logging (`BAN`) with `RULE=DDOS`, `SOURCE=KERNEL`.
- ddos observability: make Stage 2 logging outcome-accurate; `BAN` is now emitted only after runtime ban apply succeeds, and failures are emitted as `BAN_FAIL` with error reason.
- ddos observability: suppress duplicate Stage 1 `THROTTLE` logs for IPs that are already under active DDOS runtime ban.
- ddos observability: stop emitting DDOS event notices (`stage1 throttle`, `stage2 ban/fail`) via daemon journal `log.Printf`; DDOS events now stay in `ban_log` (`/var/log/mef.log`) and optional `debug_log`.
- ddos observability: enrich `THROTTLE`/`BAN` `msg` with Stage 1 trigger context from kernel detail sets (port + limit family + configured threshold values); add explicit `hit_model=episodes` tag to clarify that `throttle_hits` counts Stage 1 episodes (set re-entry), not raw packet count.
- community reporting: add DDOS integration for successful Stage 2 bans (`service=ddos`); DDOS `THROTTLE`/`BAN_FAIL` are not community-reported.
- mefctl: add DDoS throttle scope management for ban operations: `bans list --ddos`, `bans delete --ddos`, `bans clear --ddos`; default `bans delete <ip>` now targets runtime + DDoS throttle sets, and `--all` also includes DDoS throttle sets.
- ddos behavior: add `ddos_stage1_mode=throttle|drop` (default `throttle`) to choose Stage 1 action model:
  - `throttle`: drop only over-limit packets/connections
  - `drop`: temporary full source drop while source is in throttle set
- ddos behavior: add `ddos_stage1_timeout=<duration>` to control Stage 1 throttle-set lifetime (and full-drop duration when `ddos_stage1_mode=drop`).
- ddos behavior: `ddos_bantime` now also supports `permanent` for Stage 2 persistent blacklist escalation.

## v1.0.6 - 2026-02-26
- config audit: add drift warnings for `mef.conf` keys; `mefdaemon` now logs missing/unknown `[global]` keys at startup/reload, and `mefctl config check [FILE]` reports the same audit on demand.
- mefdaemon: add Linux permanent-blacklist fastpath framework with `blacklist_fastpath=auto|xdp|tc|disabled` and `blacklist_fastpath_xdp_mode=auto|native|generic`; runtime sync now writes status to `cache_dir/blacklist_fastpath_status.json` and `mefctl status` shows active/configured mode, interfaces, `entries_v4`, `entries_v6`, `prefixes`, and `last_sync`.
- mefctl: add `status --verbose fastpath` target view for fastpath lifecycle/debug details (`kernel_table`, source-of-truth, restart/crash behavior, and fastpath management commands).
- docs: update README + config template with fastpath operations and mefctl command usage (`status --verbose fastpath`, runtime/permanent ban management, emergency reset flow).
- mefdaemon: add `tc` fastpath implementation for permanent blacklist sets (`mefpermbanned_*`, `mefbl_*`) via netdev ingress nft sets/chains; `auto` currently falls back to `tc` when XDP is unavailable.
- mefdaemon: when fastpath is active, permanent blacklist enforcement is now single-path; nft permanent sets in `inet mef` are cleaned up to avoid duplicate active entries in both `inet mef` and `netdev mef_fastpath`.
- PS/packet: add Linux eBPF socket-filter kernel drop v2 (IPv4 + IPv6, exact IP + CIDR via LPM trie) built from permanent blacklist + runtime timeout ban snapshots; already-blocked sources are dropped before userspace packet processing with live map diff updates (no packet-source restart for snapshot-only changes).
- PS/packet: add userspace early blocked-IP skip path in packet reader (minimal parse + in-memory snapshot lookup) so packets from already blocked sources are discarded before event build/channel pipeline; periodic stats now expose `skip_banned_early`.
- config: add `ps_packet_kernel_drop=true|false` (default `true`) to control packet-source blocked-IP kernel drop/early-skip path independently from blacklist fastpath (`blacklist_fastpath`).
- mefctl: harden `bans add --permanent` with whitelist conflict guard; permanent entries overlapping whitelist CIDRs are now rejected.
- mefctl: add `bans list --fastpath` for direct kernel fastpath visibility (`netdev mef_fastpath`) and make `bans list`/`bans list --permanent` always include permanent entries from `blacklist/*.conf` even when fastpath is the active enforcement path.
- mefdaemon: add guarded heap trim on large blacklist shrink events (`sighup`/periodic reload) with cooldown/thresholds (`old>=10k`, `removed>=5k`, `drop>=25%`, cooldown `10m`) to return memory to OS without constant GC pressure.
- docs: add explicit backend feature matrix (`nftables` vs `iptables`), valid-combo quick reference, and kernel datapath explanation for packet source copy-path behavior and related tuning (`ps_packet_kernel_drop`, `blacklist_fastpath`).

## v1.0.5 - 2026-02-25
- mefdaemon: permanent blacklist sync is now file-aware. `auto-permanent.conf` stays on `mefpermbanned_v4/v6`, while other blacklist files map to dedicated dynamic sets `mefbl_<filename>_v4/v6`.
- mefdaemon: `blacklist_reload` now applies per-file diffing; unchanged files are skipped and only changed files are re-synced.
- mefdaemon: permanent set synchronization now uses diff add/delete for small updates and atomic tmp+swap for large updates.
- mefdaemon: optimize large nft permanent set sync by batching element loads via `nft -f` chunked scripts instead of per-element `nft` process calls.
- mefdaemon: fix nft compatibility for large permanent sync on hosts where `nft swap set ...` is unsupported; now falls back to `flush set + batched add`, avoiding repeated sync failures.
- mefdaemon: optimize fallback large nft sync path to run `flush set` + chunked `add element` in a single `nft -f` transactional script (one process, one batch apply).
- mefdaemon: full/reload permanent sync now removes orphan dynamic blacklist sets (`mefbl_*`) and their firewall bindings when source `blacklist/*.conf` files are deleted.
- mefdaemon: harden orphan-set cleanup by removing stale nft set references from any chain in target table before set delete, then flushing as fallback to prevent old elements from lingering.
- mefdaemon: nft permanent blacklist updates now apply existing target files in one `nft -f` transaction (`flush set` + chunked `add element` across sets); deleted files are handled only by orphan cleanup and are no longer re-targeted as empty sets.
- mefdaemon: reduce runtime nft CPU spikes by removing per-ban `ensureNftSetAndRules` calls; BAN now writes directly to nft set and only does one lazy ensure+retry if target nft object is missing.
- RBL/CLOUD: add blacklist fast-path before DNS lookup/ban apply; IPs already present in persistent blacklist are now skipped (no extra DNS query, no duplicate BAN log/action).
- logging: when RBL/CLOUD path is skipped due persistent blacklist membership, emit rate-limited `RULE=BLACKLIST | SOURCE=FILE | DROP | action=skip | ...` entries for audit visibility.
- community reporting: `RULE=BLACKLIST` skips now report as `service=blacklist` sightings with `1 report/hour/IP` limiter and persistent cache at `cache_dir/community_report_sightings.json` (24h retention, capped size).
- PS/conntrack: skip host-originated outbound conntrack NEW events before interface filtering (debug output stays `SKIP_INTERFACE` for consistency with existing filter logs).
- PS/conntrack: normalize debug `msg` formatting to compact structured form (`TCP/UDP src=... dst=... sport=... dport=... [state=...]`) without raw-line extra spacing.
- docs: clarify PS source trade-offs (`packet` visibility vs `conntrack` CPU), `ps_exclude_ports=auto` impact on service-port scans, and strict ban threshold semantics (`unique_ports > ps_limit`).
- mefctl: `bans delete` scope semantics updated: default = runtime only, `--permanent` = permanent sets + blacklist files only, `--all` = runtime + permanent + blacklist files.
- mefctl: `bans list` adds `--permanent` and `--all` scopes, and now includes dynamic permanent sets (`mefbl_*`) in permanent views.
- tests/docs: add coverage for blacklist snapshot diffing, dynamic permanent set naming, and new `bans` scope resolution; update README command/config behavior notes.

## v1.0.4 - 2026-02-22
- mefdaemon: add optional dynamic RBL/DNSBL profiles (`rbl_<key>_*`, key `[a-z0-9]+`) with async fail-open DNS lookups, per-profile cache (`positive_ttl`, `negative_ttl`, `error_ttl`), and port-scoped bans.
- mefdaemon: add normalized RBL BAN logging (`RULE=RBL | SOURCE=DNS | BAN | ... | profile=<key> | msg="zone=... answer=..."`) and use stable community reporting `service=rbl` for all non-cloud RBL profiles (profile context stays in `details.zone`).
- mefdaemon: extend RBL BAN `msg` with trigger context fields when available: `src`, `dport`, `proto`, `dst`, `iface`.
- mefdaemon: trigger RBL checks also from `rules.d/*` match hits (`source=file` and `source=journal`) when `rbl_enabled=true` (not only from PS source stream).
- mefdaemon: set default RBL profile to `rbl_blocklist_*` (`zone=bl.blocklist.de`).
- mefdaemon: add `community_cloud_protection=true/false` (requires `community_report=true`) for Malware.Expert DNS cloud checks (`RULE=CLOUD | SOURCE=DNS`) and keep community reporting endpoint fixed.
- mefdaemon: align community reporting transport with cloud ingress API and support both single-event object and multi-event array submissions.
- mefdaemon: add optional `details` JSON object to community reporting payload with strict per-rule mapping (omitted when empty); currently `RBL/CLOUD -> zone,answer,dport` and `PORTSCAN -> ports,interval,limit`.
- mefdaemon: improve community reporting delivery resilience with transient retries and DNS multi-IP dial failover attempts.
- docs/config: expose `community_cloud_*` tuning keys in public `mef.conf` template and README (`ports`, `bantime`, `timeout`, `positive_ttl`, `negative_ttl`, `error_ttl`).
- mefdaemon: allow startup without enabled `rules.d` rules (or even without `*.conf` files); daemon now runs with rule watchers disabled and keeps global detectors (PS/RBL/CLOUD) available when enabled.
- PS/packet: optimize hot path CPU usage by caching `ifindex -> ifname` lookups in packet source reader.
- PS/packet: drop `PACKET_OUTGOING` frames before packet parsing to avoid processing host-originated egress traffic.
- PS: add debug fast-path gating so disabled debug mode avoids expensive formatting/mutex work in high-frequency event loops.
- PS/packet: build `event.Raw` payload only when debug is enabled.
- PS/packet: bind packet sockets to resolved `ps_interface` set (when not `all`), attach kernel cBPF filter (TCP SYN, optional UDP, VLAN-aware) with `ps_exclude_ports` support, and hot-reload packet source when interface/auto-exclude ports change.
- PS/debug: reduce duplicate packet `HIT` logs by emitting `HIT` only when a new unique destination port is observed; repeated same-port SYNs are now counted in `port scan stats` as `repeat_port`.

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
