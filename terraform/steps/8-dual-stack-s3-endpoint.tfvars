# Step 8: as step 6, plus the S3 gateway endpoint a dual-stack subnet would normally get, of type "dualstack". The probe
# bucket only lets the instances read through it, so a probe read that works went through the endpoint. Does S3's
# default name, and an ECR pull through the default registry name, still go through the NAT gateway?
step                          = "8-dual-stack-s3-endpoint"
enable_ipv6_only_client       = false
enable_dual_stack_instances   = true
enable_dual_stack_s3_endpoint = true
