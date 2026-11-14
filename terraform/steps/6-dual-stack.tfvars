# Step 6: the dual-stack subnet on its own, the way most teams start: IPv4 through the NAT gateway as before, IPv6
# through the egress-only internet gateway. Two instances: "dual-stack" runs every check, including the S3 and ECR
# downloads; "dual-stack-ipv4-rules" has a security group that only allows IPv4 out, as many existing ones do. The
# IPv6-only client is off, so the NAT gateway's byte counts are the dual-stack instance's alone.
step                        = "6-dual-stack"
enable_ipv6_only_client     = false
enable_dual_stack_instances = true
