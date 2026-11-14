# Step 7: as step 6, plus DNS64 on the dual-stack subnet, which still has no route for 64:ff9b::/96. Names without an
# AAAA record get a made-up one, and the instances have to decide between it and the real A record.
step                        = "7-dual-stack-dns64"
enable_ipv6_only_client     = false
enable_dual_stack_instances = true
enable_dual_stack_dns64     = true
