#!/usr/bin/env bash
# Egress firewall: drop everything outbound except DNS, loopback, and HTTPS to the allowlisted hosts.
# Needs NET_ADMIN (docker run --cap-add NET_ADMIN). Hosts are resolved once at start; extend the list with
# AB_ALLOW_DOMAINS="api.anthropic.com other.example". DNS is allowed to anywhere, so DNS lookups remain a
# (slow, low-bandwidth) side channel -- the firewall stops file fetches, git clones and web requests, not that.
# Only the `filter` table is touched: Docker's embedded-DNS rules live in `nat` and must be left alone.
set -euo pipefail

ALLOW_DOMAINS="${AB_ALLOW_DOMAINS:-api.anthropic.com}"

ipset create ab_allowed hash:ip -exist
ipset flush ab_allowed

count=0
for domain in $ALLOW_DOMAINS; do
  ips=$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u || true)
  [[ -n "$ips" ]] || { echo "init-firewall: cannot resolve $domain" >&2; exit 1; }
  for ip in $ips; do ipset add ab_allowed "$ip" -exist; count=$((count + 1)); done
done

iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set ab_allowed dst -j ACCEPT

# IPv6 is closed completely (the allowlist is IPv4 only).
ip6tables -F 2>/dev/null || true
ip6tables -P INPUT DROP 2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP 2>/dev/null || true

# Self-test: a general site must fail and the API must connect (any HTTP status counts as connected).
if curl -s -o /dev/null --max-time 5 https://example.com; then
  echo "init-firewall: example.com is reachable, so the firewall is not working" >&2; exit 1
fi
if ! curl -s -o /dev/null --max-time 10 https://api.anthropic.com; then
  echo "init-firewall: api.anthropic.com is not reachable (allowed IPs: $count)" >&2; exit 1
fi
echo "init-firewall: egress limited to: $ALLOW_DOMAINS"
