# Step 1: an egress-only internet gateway and nothing else. Names with an IPv6 address work; the rest don't resolve.
step               = "1-eigw-only"
enable_dns64       = false
enable_nat64_route = false
