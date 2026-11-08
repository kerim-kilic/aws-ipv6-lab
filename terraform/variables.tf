variable "name" {
  description = "Prefix for everything the lab creates."
  type        = string
  default     = "aws-ipv6-lab"
}

variable "aws_region" {
  description = "Region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "allowed_account_id" {
  description = "Account to run in. The provider refuses any other."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.allowed_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "vpc_cidr" {
  description = "IPv4 range for the VPC. Only the public subnets use it: the workload subnets are IPv6-only."
  type        = string
  default     = "10.30.0.0/24"
}

variable "instance_type" {
  description = "Instance type for the test instances. Must be Nitro-based to run in an IPv6-only subnet."
  type        = string
  default     = "t3.micro"
}

variable "check_interval" {
  description = "How often the instances run their checks and upload the results, as a systemd time span."
  type        = string
  default     = "5min"
}

# Set per step, see steps/.

variable "step" {
  description = "Lab step. Tagged on the instances, which read it from instance metadata and file their results under it."
  type        = string
  default     = "1-eigw-only"
}

variable "enable_dns64" {
  description = "DNS64 on the IPv6-only subnets: Route 53 Resolver synthesises 64:ff9b::/96 answers for IPv4-only names."
  type        = bool
  default     = false
}

variable "enable_nat64_route" {
  description = "Route 64:ff9b::/96 from the IPv6-only subnets to the NAT gateway, which translates it to IPv4 (NAT64)."
  type        = bool
  default     = false
}

variable "enable_imds_ipv4_instance" {
  description = "Add a second instance with the IPv6 metadata endpoint left off, as an instance gets it by default."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Add an S3 gateway endpoint and STS, SSM and ECR interface endpoints, all IPv6, for the IPv6-only subnets (step 4)."
  type        = bool
  default     = false
}

variable "enable_control_instance" {
  description = "Add a control instance in a dual-stack subnet without DNS64, which reaches IPv4 hosts over plain IPv4 through the same NAT gateway."
  type        = bool
  default     = false
}
