locals {
  # "client" runs the checks in every step. "imds-ipv4" is the same instance with the metadata service left as an
  # instance gets it by default, IPv4 endpoint only (step 5). "control" is dual-stack, without DNS64, and skips the
  # large downloads so the NAT gateway's byte counts stay the client's. In steps 6 to 8, "dual-stack" runs every
  # check from the dual-stack subnet, and "dual-stack-ipv4-rules" does the same without the downloads, behind a
  # security group that only allows IPv4 out.
  instance_sg      = [aws_security_group.instance.id]
  ipv4_rules_sg    = [aws_security_group.ipv4_rules.id]
  dual_stack_extra = { imds_ipv6 = true, subnet_id = aws_subnet.control.id }
  instances = merge(
    var.enable_ipv6_only_client ? { client = { imds_ipv6 = true, subnet_id = aws_subnet.workload[0].id, role = "client", sg = local.instance_sg } } : {},
    var.enable_imds_ipv4_instance ? { imds-ipv4 = { imds_ipv6 = false, subnet_id = aws_subnet.workload[0].id, role = "client", sg = local.instance_sg } } : {},
    var.enable_control_instance ? { control = { imds_ipv6 = true, subnet_id = aws_subnet.control.id, role = "control", sg = local.instance_sg } } : {},
    var.enable_dual_stack_instances ? {
      dual-stack            = merge(local.dual_stack_extra, { role = "client", sg = local.instance_sg })
      dual-stack-ipv4-rules = merge(local.dual_stack_extra, { role = "ipv4-rules", sg = local.ipv4_rules_sg })
    } : {},
  )
}

resource "aws_security_group" "instance" {
  name        = "${var.name}-instance"
  description = "Lab instances: outbound only"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-instance" }
}

# ::/0 includes 64:ff9b::/96. A security group with narrower outbound rules has to allow that prefix for NAT64 to work.
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# For the control instance, which has an IPv4 address. A security group's IPv4 and IPv6 rules are separate: without
# this one, the control instance reaches everything over IPv6 and nothing over IPv4.
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound IPv4 only, like many security groups written before a VPC had IPv6. Once the subnet has IPv6, the instance
# gets an IPv6 address and finds AAAA records, and this group drops what it sends to them.
resource "aws_security_group" "ipv4_rules" {
  name        = "${var.name}-ipv4-rules"
  description = "Lab instances: outbound IPv4 only"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-ipv4-rules" }
}

resource "aws_vpc_security_group_egress_rule" "ipv4_rules_all_ipv4" {
  security_group_id = aws_security_group.ipv4_rules.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "lab" {
  for_each = local.instances

  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  subnet_id              = each.value.subnet_id
  ipv6_address_count     = 1
  vpc_security_group_ids = each.value.sg
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/../instance/user-data.sh.tftpl", {
    checks_gz = base64gzip(file("${path.module}/../instance/lab-checks.sh"))
    bucket    = aws_s3_bucket.results.id
    probe     = aws_s3_bucket.probe.id
    role      = each.value.role
    ecr_repo  = aws_ecr_repository.test.name
    registry  = aws_ecr_repository.test.registry_id
    region    = var.aws_region
    interval  = var.check_interval
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_protocol_ipv6          = each.value.imds_ipv6 ? "enabled" : "disabled"
    # The checks read the LabStep tag from instance metadata, so a new step needs no new instance.
    instance_metadata_tags = "enabled"
  }

  private_dns_name_options {
    hostname_type                        = "resource-name"
    enable_resource_name_dns_aaaa_record = true
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name    = "${var.name}-${each.key}"
    LabStep = var.step
  }

  lifecycle {
    # A new Amazon Linux release mid-session shouldn't replace the instance.
    ignore_changes = [ami]
  }

  depends_on = [aws_route_table_association.workload, aws_route_table_association.control, aws_iam_role_policy.results]
}
