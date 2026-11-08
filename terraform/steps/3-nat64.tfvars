# Step 3: 64:ff9b::/96 routed to the NAT gateway. The IPv4-only internet works, translated by NAT64. A control
# instance in a dual-stack subnet reaches the same IPv4 hosts over plain IPv4, through the same NAT gateway.
step                    = "3-nat64"
enable_dns64            = true
enable_nat64_route      = true
enable_control_instance = true
