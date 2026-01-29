# mef firewall rules – specification (v1)

This document defines the mef firewall rule language.
It is the authoritative specification for parsing, validating and applying
mef.rules.

The actual firewall configuration is stored in /etc/mef/mef.rules.

----------------------------------------------------------------------
1. Design goals
----------------------------------------------------------------------
- Simple, explicit, human-readable syntax
- One rule per line
- Same fields in every rule (canonical form)
- Works with nftables (primary) and iptables/ip6tables
- Safe defaults (deny inbound, allow established)
- IPv4 and IPv6 fully supported

Defaults are explicit and documented. The formatter makes them visible.

----------------------------------------------------------------------
2. File format
----------------------------------------------------------------------
- UTF-8 text
- One statement per line
- Empty lines are ignored
- Lines starting with # are comments
- Tokens are whitespace-separated key=value pairs
- Unknown keys are an error
- Missing required keys are an error

2.1 File location
The actual firewall configuration is stored in:
  /etc/mef/mef.rules

----------------------------------------------------------------------
3. Statements
----------------------------------------------------------------------

3.1 policy

policy dir=<in|out|fwd> action=<accept|drop|reject>

Defines the default action if no rule matches.

Example:
policy dir=in action=drop

Typical minimal file:
  policy dir=in action=drop
  policy dir=out action=accept
  policy dir=fwd action=drop

----------------------------------------------------------------------
3.2 rule

Defines a packet filtering rule.

A rule is written as whitespace-separated key=value pairs on one line:

  rule <key=value> <key=value> ...

User-written rules MAY omit optional fields. Missing fields are filled with
default values during parsing and/or by `mef firewall fmt`.

Canonical form (normalized output / internal representation):

  rule dir=... family=... action=... log=... ratelimit=... proto=...
       iif=... oif=... src=... dst=... sport=... dport=... ct=... comment="..."

In canonical form, ALL fields are present. This makes diffing, validation and
backend generation deterministic.

Required in user-written rules:
  - dir
  - action
  - proto

Optional in user-written rules (defaults applied if missing):
  - family     (default: any)
  - log        (default: none)
  - ratelimit  (default: any)
  - iif        (default: any)
  - oif        (default: any)
  - src        (default: any)
  - dst        (default: any)
  - sport      (default: any)
  - dport      (default: any)
  - ct         (default: any)
  - comment    (default: "")

Notes:
  - sport/dport are only meaningful for proto=tcp or proto=udp. For other
    protocols they must be 'any' (validator enforces this).
  - `mef firewall fmt` expands every rule into canonical form (all fields
    present and in a fixed order).

Example (user-written, minimal):
  rule dir=in action=accept proto=tcp dport=22 src=any

Example (canonical form):
  rule dir=in family=any action=accept log=none ratelimit=any proto=tcp
       iif=any oif=any src=any dst=any sport=any dport=22 ct=any comment=""

----------------------------------------------------------------------
3.3 set (optional)

Named reusable sets (mainly address sets).

set name=<name> family=<any|ip|ip6> type=<addr|port> elements=<list>

Examples:
set name=admin_net family=ip type=addr elements=1.2.3.0/24,5.6.7.8
set name=mail_ports family=any type=port elements=25,465,587

----------------------------------------------------------------------
4. Rule fields (complete reference)
----------------------------------------------------------------------

4.1 dir
dir=<in|out|fwd>

in   = INPUT chain (traffic destined to this host)
out  = OUTPUT chain (traffic originating from this host)
fwd  = FORWARD chain (routed traffic)

----------------------------------------------------------------------
4.2 family
family=<any|ip|ip6>

any = IPv4 and IPv6
ip  = IPv4 only
ip6 = IPv6 only

----------------------------------------------------------------------
4.3 action
action=<accept|drop|reject>

accept = allow packet
drop   = silently drop packet
reject = actively reject (TCP RST or ICMP unreachable)

----------------------------------------------------------------------
4.4 log
log=<none|prefix:STRING>

Controls logging behavior.

none            = no logging
prefix:MEF_FW   = log packet with prefix MEF_FW

Logging is orthogonal to action.

----------------------------------------------------------------------
4.5 ratelimit
ratelimit=<any|RATE>

Limits logging rate only, never packet handling.

any     = no rate limit
RATE    = examples: 5/s, 30/m, 100/h

----------------------------------------------------------------------
4.6 proto
proto=<all|tcp|udp|icmp|icmp6>

all   = any protocol
tcp
udp
icmp  = IPv4 ICMP
icmp6 = IPv6 ICMP

----------------------------------------------------------------------
4.7 iif / oif

iif=<any|auto|IFSPEC>
oif=<any|auto|IFSPEC>

IFSPEC may be:
- a single interface name: ens0
- a comma-separated list: ens0,ens1
- (optional) negation: !lo or !lo,docker0
- auto (Linux only): resolve to default route interface

Semantics:
- any       = match any NON-loopback interface
- auto      = match the default route interface (Linux)
- lo        = match loopback interface only
- ens0      = match only ens0
- ens0,ens1 = match ens0 or ens1
- !lo       = match any non-loopback interface

Note:
Loopback traffic is NOT matched by iif=any or oif=any.
Loopback must always be explicitly matched with iif=lo / oif=lo.
If auto cannot be resolved, validation should fail and you must set iif/oif explicitly.

----------------------------------------------------------------------
4.8 src / dst

src (source address)
dst (destination address)

Syntax:
  src=<any|IP|CIDR|@set>
  dst=<any|IP|CIDR|@set>

Supported values:

any
  Match all source/destination addresses.
  Equivalent to:
    IPv4: 0.0.0.0/0
    IPv6: ::/0

1.2.3.4
  Single IPv4 address.

2001:db8::1
  Single IPv6 address.

1.2.3.0/24
  IPv4 network in CIDR notation.

2001:db8::/64
  IPv6 network in CIDR notation.

@setname
  Named address set.
  The set must be defined using a `set` statement and may be implemented
  as an nftables set or ipset, depending on backend.

Notes:
  - IPv4 and IPv6 addresses may be mixed only when family=any.
  - When family=ip, only IPv4 values are allowed.
  - When family=ip6, only IPv6 values are allowed.
  - Address sets inherit their address family from the set definition.

----------------------------------------------------------------------
4.9 sport / dport
sport=<any|PORTSPEC>
dport=<any|PORTSPEC>

PORTSPEC formats:
- single port (22)
- list (25,587,993)
- range (10000-20000)

Only valid for proto=tcp or proto=udp.

----------------------------------------------------------------------
4.10 ct
ct=<any|state[,state...]>

states:
new, established, related, invalid

----------------------------------------------------------------------
4.11 comment
comment="free text"

Notes:
  - Use double quotes for comments.
  - If the comment contains double quotes, escape them as \".

----------------------------------------------------------------------
5. Evaluation order
----------------------------------------------------------------------
1. mef dynamic ban rules (priority -100)
2. rules from mef.rules
3. default policy

----------------------------------------------------------------------
6. Backend mapping
----------------------------------------------------------------------

nftables:
- table inet mef
- input/output/forward chains
- native log, limit, ct

iptables(fallback):
- iptables + ip6tables
- rules duplicated per family

----------------------------------------------------------------------
7. Validation rules (summary)
----------------------------------------------------------------------
- Unknown keys are errors
- Missing required keys are errors
- Ports only valid for tcp/udp
- icmp/icmp6 must match family
- set references must exist

----------------------------------------------------------------------
8. Versioning
----------------------------------------------------------------------
This document defines mef firewall rules v1.
