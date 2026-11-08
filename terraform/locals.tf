locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 10.30.0.0/24: a /28 per public subnet, and one for the control subnet. The IPv6-only subnets have no IPv4 range.
  public_cidrs = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  control_cidr = cidrsubnet(var.vpc_cidr, 4, 2)

  # The VPC gets a /56 from Amazon; each subnet takes a /64 from it (256 available).
  #   00, 01   public (dual-stack)
  #   10, 11   workload (IPv6-only)
  #   20       control (dual-stack, no DNS64)
  public_ipv6_cidrs   = [for i, _ in local.azs : cidrsubnet(aws_vpc.lab.ipv6_cidr_block, 8, i)]
  workload_ipv6_cidrs = [for i, _ in local.azs : cidrsubnet(aws_vpc.lab.ipv6_cidr_block, 8, 16 + i)]
  control_ipv6_cidr   = cidrsubnet(aws_vpc.lab.ipv6_cidr_block, 8, 32)

  # RFC 6052 well-known prefix: DNS64 synthesises answers in it, and the NAT gateway translates it.
  nat64_prefix = "64:ff9b::/96"
}
