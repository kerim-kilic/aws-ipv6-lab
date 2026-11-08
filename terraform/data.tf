data "aws_availability_zones" "available" {
  state = "available"

  # Older zone with a limited choice of instance types. Zone IDs, because AZ names differ per account.
  exclude_zone_ids = ["use1-az3"]
}

# The current Amazon Linux 2023 image. It comes with the AWS CLI v2, curl and Python, which is all the checks use.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
