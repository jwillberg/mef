# mef

Fail2Ban/CSF-style log analyzer and auto-banning daemon.

## Install
### Quick install (after extract)
```bash
cd /tmp/mef-release
chmod +x install.sh uninstall.sh
sudo ./install.sh
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
sudo mkdir -p /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist
sudo cp -f bin/mefdaemon /usr/local/sbin/mefdaemon
sudo cp -f bin/mefctl /usr/local/sbin/mefctl
sudo chmod 0755 /usr/local/sbin/mefdaemon /usr/local/sbin/mefctl

sudo cp -n conf/mef.conf /etc/mef/mef.conf
sudo cp -n conf/mef.rules /etc/mef/mef.rules
sudo cp -n conf/rules.d/*.conf /etc/mef/rules.d/
sudo cp -n conf/whitelist/example.conf /etc/mef/whitelist/example.conf

sudo cp -f services/systemd/mefdaemon.service /etc/systemd/system/mefdaemon.service
sudo systemctl daemon-reload
sudo systemctl enable --now mefdaemon
```

#### FreeBSD
```sh
sudo install -d /usr/local/sbin /etc/mef /etc/mef/rules.d /etc/mef/whitelist
sudo install -m 0755 bin/mefdaemon /usr/local/sbin/mefdaemon
sudo install -m 0755 bin/mefctl /usr/local/sbin/mefctl
sudo install -m 0644 conf/mef.conf /etc/mef/mef.conf
sudo install -m 0644 conf/mef.rules /etc/mef/mef.rules
sudo install -m 0644 conf/rules.d/*.conf /etc/mef/rules.d/
sudo install -m 0644 conf/whitelist/example.conf /etc/mef/whitelist/example.conf

sudo install -m 0755 services/freebsd/mefdaemon.rc /usr/local/etc/rc.d/mefdaemon
echo 'mefdaemon_enable="YES"' | sudo tee -a /etc/rc.conf >/dev/null
sudo service mefdaemon start
```

## Commands
- Flush bans (systemd): `systemctl reload mefdaemon`
- Clear firewall rules (mefctl): `mefctl rules clear`
- Clear entire nftables table (mefctl): `mefctl rules clear --all [--force]`
- Clear bans only (mefctl): `mefctl bans clear`

## Config
- Global config: `/etc/mef/mef.conf`
- Per-service rules: `/etc/mef/rules.d/*.conf`

Repo default config template: [conf/mef.conf](conf/mef.conf)

Global config (INI-style):
- `rules_dir` (default `/etc/mef/rules.d`)
- `whitelist_dir` (default `/etc/mef/whitelist`)
- `whitelist_reload` (default `1m`, supports `10s`, `1m`, or integer seconds)
- `debug_log` (default `/tmp/mef.txt`)
- `journal_since` (default `2 min ago`)
- `firewall_backend` (`auto` | `nftables` | `iptables`)
- `firewall_family` (nftables table family, default `inet`)
- `firewall_table` (nftables table name, default `mef`)
- `firewall_chain` (nftables chain name / iptables chain, default `mef`)
- `firewall_hook` (nftables hook, default `input`)
- `firewall_priority` (nftables hook priority, default `-100`)
- `firewall_log_enabled` (enable LOG before DROP, default `true`)
- `firewall_log_prefix` (LOG prefix, default `MEF DROP `)
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

## Code documentation
Keeping the code well-documented is important for this project. Please add clear file headers and comments for non-obvious logic so future maintenance and search are easy.
