#!/usr/bin/env python3
"""Copies captures/raw to captures/scrubbed with account, resource and public address details replaced.

Each real value gets a stable placeholder (subnet-EXAMPLE1, 203.0.113.1, ...), so readers can still follow which
resource is which across files.

IPv6 needs more care than IPv4: there are no private ranges to leave alone, and the VPC's /56 is globally unique. Every
global IPv6 address is moved into the documentation range 2001:db8::/32, one /56 per real /56, keeping the subnet ID
and the interface ID, so 2600:1f18:aaaa:bb10::1234 becomes something like 2001:db8:1:10::1234. NAT64 addresses keep
their 64:ff9b:: prefix, and the IPv4 address inside them is replaced like any other, so a synthesised AAAA record still
matches its A record: 64:ff9b::203.0.113.1. Unique local (fd00:ec2::254), link-local and private IPv4 addresses stay.
"""

import ipaddress
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "captures" / "raw"
OUT = ROOT / "captures" / "scrubbed"

KEEP_V4 = [
    ipaddress.ip_network(n)
    for n in ("10.0.0.0/8", "100.64.0.0/10", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "127.0.0.0/8",
              "0.0.0.0/8", "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "198.18.0.0/15")
]
# Placeholders for public IPv4 addresses: the three documentation ranges (RFC 5737), 762 addresses in all, then the
# benchmarking range 198.18.0.0/15 (RFC 2544), which is never routed on the internet either. S3 and other large
# services answer with a different set of addresses on every lookup, so a long run uses more than the first range.
DOC_V4 = ["203.0.113", "198.51.100", "192.0.2"]
DOC_V4_NETS = [ipaddress.ip_network(f"{prefix}.0/24") for prefix in DOC_V4]


BENCH_V4 = int(ipaddress.IPv4Address("198.18.0.0"))


def doc_v4(n: int) -> str:
    if n <= 254 * len(DOC_V4):
        prefix, host = divmod(n - 1, 254)
        return f"{DOC_V4[prefix]}.{host + 1}"
    n -= 254 * len(DOC_V4)
    if n >= 2 ** 17 - 1:
        raise SystemExit("More distinct public IPv4 addresses than placeholders.")
    return str(ipaddress.IPv4Address(BENCH_V4 + n))
KEEP_V6 = [
    ipaddress.ip_network(n)
    for n in ("::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "2001:db8::/32")
]
NAT64 = ipaddress.ip_network("64:ff9b::/96")
MAPPED = ipaddress.ip_network("::ffff:0:0/96")
DOC_V6 = int(ipaddress.IPv6Address("2001:db8::"))

mappings: dict[str, dict[object, str]] = {}


def placeholder(kind: str, value, fmt) -> str:
    table = mappings.setdefault(kind, {})
    if value not in table:
        table[value] = fmt(len(table) + 1)
    return table[value]


def scrub_v4(text: str) -> str:
    try:
        ip = ipaddress.IPv4Address(text)
    except ValueError:
        return text
    if any(ip in net for net in KEEP_V4):
        return text
    return placeholder("ipv4", text, doc_v4)


def scrub_v6(text: str) -> str:
    try:
        ip = ipaddress.IPv6Address(text)
    except ValueError:
        return text
    if any(ip in net for net in KEEP_V6):
        return text
    for prefix, label in ((NAT64, "64:ff9b::"), (MAPPED, "::ffff:")):
        if ip in prefix:
            inner = str(ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF))
            replaced = scrub_v4(inner)
            # The prefix on its own (64:ff9b::) or a private address inside it: nothing to hide, keep it as written.
            return text if replaced == inner else label + replaced
    # A new 2001:db8:<n>::/56 for each real /56; the subnet ID (next 8 bits) and the interface ID stay.
    n = int(placeholder("ipv6-prefix", int(ip) >> 72, lambda n: str(n)))
    return str(ipaddress.IPv6Address(DOC_V6 | (n << 80) | (int(ip) & ((1 << 72) - 1))))


# Anything with two colons that is not glued to a word: a timestamp like 10:11:12 fails to parse and is left alone.
V6_CANDIDATE = re.compile(r"(?<![\w:.])[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*(?![\w:])")


def v6_token(match: re.Match) -> str:
    token = match.group(0)
    # Trailing punctuation, as in "address 2600:1f18::1." or "fd00:ec2::254:".
    core = token.rstrip(".:") or token
    for candidate in (token, core):
        try:
            ipaddress.IPv6Address(candidate)
        except ValueError:
            continue
        return scrub_v6(candidate) + token[len(candidate):]
    return token


RULES = [
    # Principals and sessions, before the account ID rule eats their digits.
    (re.compile(r"arn:aws:(iam|sts)::\d{12}:(user|assumed-role|role|federated-user)/[^\s\"',]+"),
     lambda m: placeholder("principal", m.group(0),
                           lambda n: f"arn:aws:{m.group(1)}::111122223333:{m.group(2)}/EXAMPLE{n}")),
    (re.compile(r"\b(AROA|AIDA|AKIA|ASIA|AGPA|ANPA)[A-Z0-9]{12,}(:[^\s\"',]+)?"),
     lambda m: placeholder("unique-id", m.group(0), lambda n: f"AROAEXAMPLE{n}")),
    (re.compile(r"\b\d{12}\b"), lambda m: "111122223333"),
    (re.compile(r"\b(vpc|subnet|eni|i|sg|sgr|nat|eipalloc|eipassoc|igw|eigw|rtb|rtbassoc|vpce|pl|fl|dopt|acl|attach|"
                r"vpc-cidr-assoc|subnet-cidr-assoc|ami|vol|snap)-[0-9a-f]{8,17}\b"),
     lambda m: placeholder(m.group(1), m.group(0), lambda n: f"{m.group(1)}-EXAMPLE{n}")),
    (re.compile(r"\bec2-\d+-\d+-\d+-\d+\.[a-z0-9.-]+\.amazonaws\.com\b"),
     lambda m: placeholder("public-dns", m.group(0), lambda n: f"ec2-EXAMPLE{n}.compute.amazonaws.com")),
    # The lab's buckets get a random suffix (bucket_prefix), unique to the account that ran it.
    (re.compile(r"\baws-ipv6-lab-(results|probe)-[0-9a-f]{10,}"),
     lambda m: placeholder("bucket", m.group(0), lambda n: f"aws-ipv6-lab-{m.group(1)}-EXAMPLE{n}")),
    # IPv6 before IPv4, so the IPv4 address inside a NAT64 address is handled with the address it belongs to.
    (V6_CANDIDATE, v6_token),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), lambda m: scrub_v4(m.group(0))),
]


def leftover_v6(match: re.Match) -> int:
    token = match.group(0).rstrip(".:")
    try:
        ip = ipaddress.IPv6Address(token)
    except ValueError:
        return 0
    if ip in NAT64 or ip in MAPPED:
        inner = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
        return 0 if any(inner in net for net in KEEP_V4) else 1
    return 0 if any(ip in net for net in KEEP_V6) else 1


def leftovers(text: str) -> int:
    count = len(re.findall(r"\b(?!111122223333)\d{12}\b", text))
    count += len(re.findall(r"\baws-ipv6-lab-(?:results|probe)-[0-9a-f]{10,}", text))
    count += sum(leftover_v6(m) for m in V6_CANDIDATE.finditer(text))
    return count


def scrub(text: str) -> str:
    for pattern, repl in RULES:
        text = pattern.sub(repl, text)
    return text


def main() -> int:
    if not RAW.is_dir():
        print("Nothing to scrub: captures/raw does not exist.", file=sys.stderr)
        return 1
    if OUT.exists():
        shutil.rmtree(OUT)

    files = 0
    suspicious = 0
    for src in sorted(p for p in RAW.rglob("*") if p.is_file()):
        dst = OUT / src.relative_to(RAW)
        dst.parent.mkdir(parents=True, exist_ok=True)
        clean = scrub(src.read_text(errors="replace"))
        dst.write_text(clean)
        files += 1
        suspicious += leftovers(clean)

    replaced = {kind: len(values) for kind, values in mappings.items()}
    print(f"Scrubbed {files} files into captures/scrubbed. Distinct values replaced: {replaced}")
    # Counts only, so nothing sensitive is printed.
    if suspicious:
        print(f"WARNING: {suspicious} suspicious values remain. Check before committing.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
