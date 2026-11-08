output "aws_region" {
  value = var.aws_region
}

output "step" {
  value = var.step
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.test.repository_url
}

output "results_bucket" {
  value = aws_s3_bucket.results.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.lab.id
}

output "instance_ids" {
  value = join(" ", [for i in aws_instance.lab : i.id])
}

output "instance_names" {
  value = join(" ", [for i in aws_instance.lab : i.tags.Name])
}

output "ami_id" {
  value = data.aws_ssm_parameter.al2023.insecure_value
}

output "vpc_endpoint_ids" {
  value = join(" ", concat(aws_vpc_endpoint.s3[*].id, [for e in aws_vpc_endpoint.interface : e.id]))
}
