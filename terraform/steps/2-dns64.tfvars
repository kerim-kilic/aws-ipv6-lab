# Step 2: DNS64 on, no route to the NAT gateway. IPv4-only names now resolve to 64:ff9b:: addresses, and connections hang.
step               = "2-dns64"
enable_dns64       = true
enable_nat64_route = false
