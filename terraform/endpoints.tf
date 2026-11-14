# Step 4: private routes to AWS APIs from the IPv6-only subnets. In an IPv6-only subnet an endpoint must use the IP
# address type "ipv6". aws ec2 describe-vpc-endpoint-services lists which services support it.

# Free. Adds a route to S3's IPv6 prefix list to the workload route table: only traffic to S3's real IPv6 addresses
# uses it, so a name without an AAAA record, answered by DNS64 with a 64:ff9b:: address, still goes through NAT64.
resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  ip_address_type   = "ipv6"
  route_table_ids   = [aws_route_table.workload.id]
  tags              = { Name = "${var.name}-s3" }
}

# Step 8: the gateway endpoint a dual-stack subnet would normally get, of type "dualstack", on the dual-stack (control)
# route table only. It adds routes to S3's IPv4 and IPv6 prefix lists, so S3's default name, which only has A records,
# can use it too.
resource "aws_vpc_endpoint" "s3_dual_stack" {
  count             = var.enable_dual_stack_s3_endpoint ? 1 : 0
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  ip_address_type   = "dualstack"
  route_table_ids   = [aws_route_table.control.id]
  tags              = { Name = "${var.name}-s3-dual-stack" }
}

locals {
  # The S3 gateway endpoints that exist in this step; the probe bucket only lets the lab instances read through them.
  s3_gateway_endpoint_ids = concat(aws_vpc_endpoint.s3[*].id, aws_vpc_endpoint.s3_dual_stack[*].id)
}

# Charged per hour per zone and per GB. One zone, where the test instances are. Private DNS answers for the default
# names (sts.<region>.amazonaws.com) and the dual-stack ones (sts.<region>.api.aws) with the endpoint's IPv6 address.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? toset(["sts", "ssm", "ecr.api", "ecr.dkr"]) : toset([])

  vpc_id              = aws_vpc.lab.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  ip_address_type     = "ipv6"
  subnet_ids          = [aws_subnet.workload[0].id]
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  dns_options {
    dns_record_ip_type = "ipv6"
  }

  tags = { Name = "${var.name}-${replace(each.key, ".", "-")}" }
}

resource "aws_security_group" "endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name}-endpoints"
  description = "Interface endpoints: HTTPS from the VPC"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC over IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = aws_vpc.lab.ipv6_cidr_block
}

# Which way did a request to S3 go? The probe bucket refuses the lab instances' reads that don't arrive through the
# gateway endpoint. Only the instance role: Terraform reads the object from outside the VPC, in refresh and destroy.
data "aws_iam_policy_document" "probe" {
  count = length(local.s3_gateway_endpoint_ids) > 0 ? 1 : 0

  statement {
    sid       = "ReadOnlyThroughTheGatewayEndpoint"
    effect    = "Deny"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.probe.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = local.s3_gateway_endpoint_ids
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.instance.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "probe" {
  count  = length(local.s3_gateway_endpoint_ids) > 0 ? 1 : 0
  bucket = aws_s3_bucket.probe.id
  policy = data.aws_iam_policy_document.probe[0].json

  depends_on = [aws_s3_bucket_public_access_block.probe]
}
