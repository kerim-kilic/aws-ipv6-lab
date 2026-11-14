resource "aws_vpc" "lab" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = var.name }
}

# Outbound-only IPv6: the IPv6 counterpart of a NAT gateway, without the translation and without a charge.
resource "aws_egress_only_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = var.name }
}

# Dual-stack. Holds the NAT gateway now and the load balancer in part 2.
resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.lab.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.public_cidrs[count.index]
  ipv6_cidr_block   = local.public_ipv6_cidrs[count.index]

  tags = { Name = "${var.name}-public-${local.azs[count.index]}" }
}

# IPv6-only: no IPv4 range, so instances here get no IPv4 address at all.
resource "aws_subnet" "workload" {
  count                           = length(local.azs)
  vpc_id                          = aws_vpc.lab.id
  availability_zone               = local.azs[count.index]
  ipv6_native                     = true
  ipv6_cidr_block                 = local.workload_ipv6_cidrs[count.index]
  assign_ipv6_address_on_creation = true
  enable_dns64                    = var.enable_dns64

  # IPv6-only subnets only support resource-based hostnames (i-0123456789abcdef0.ec2.internal).
  private_dns_hostname_type_on_launch            = "resource-name"
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = { Name = "${var.name}-workload-${local.azs[count.index]}" }
}

# One NAT gateway is enough for a lab. NAT64 is always on in a NAT gateway: it only needs traffic routed to it.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

resource "aws_nat_gateway" "lab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = var.name }

  depends_on = [aws_internet_gateway.lab]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route" "public_ipv6" {
  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Routes are separate resources, so a step can add or remove one without replacing the table.
resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-workload" }
}

resource "aws_route" "workload_ipv6" {
  route_table_id              = aws_route_table.workload.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.lab.id
}

# The more specific route wins, so traffic to 64:ff9b::/96 goes to the NAT gateway instead of the egress-only gateway.
resource "aws_route" "workload_nat64" {
  count                       = var.enable_nat64_route ? 1 : 0
  route_table_id              = aws_route_table.workload.id
  destination_ipv6_cidr_block = local.nat64_prefix
  nat_gateway_id              = aws_nat_gateway.lab.id
}

resource "aws_route_table_association" "workload" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.workload[count.index].id
  route_table_id = aws_route_table.workload.id
}

# Dual-stack, the way a private subnet looks once IPv6 is added to it: 0.0.0.0/0 to the NAT gateway, ::/0 to the
# egress-only internet gateway. In step 3 the control instance here reaches IPv4 hosts over plain IPv4, to tell problems
# that come from NAT64 apart from problems at the other end; steps 6 to 8 test the subnet itself. Free when no instance
# runs in it.
resource "aws_subnet" "control" {
  vpc_id            = aws_vpc.lab.id
  availability_zone = local.azs[0]
  cidr_block        = local.control_cidr
  ipv6_cidr_block   = local.control_ipv6_cidr
  enable_dns64      = var.enable_dual_stack_dns64

  tags = { Name = "${var.name}-control-${local.azs[0]}" }
}

resource "aws_route_table" "control" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name}-control" }
}

resource "aws_route" "control_ipv4" {
  route_table_id         = aws_route_table.control.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lab.id
}

resource "aws_route" "control_ipv6" {
  route_table_id              = aws_route_table.control.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.lab.id
}

resource "aws_route_table_association" "control" {
  subnet_id      = aws_subnet.control.id
  route_table_id = aws_route_table.control.id
}
