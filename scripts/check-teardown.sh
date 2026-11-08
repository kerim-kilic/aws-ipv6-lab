#!/usr/bin/env bash
# After terraform destroy: confirms nothing billable is left. Prints counts only.
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"

name=aws-ipv6-lab
region=${1:-$(lab_region)}
left=0

count() {
  local label=$1 n=$2
  if [[ $n == 0 ]]; then
    printf '%-40s %s\n' "$label" "none"
  else
    printf '%-40s %s\n' "$label" "$n LEFT"
    left=1
  fi
}

count "Running or stopped lab instances" "$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Project,Values=$name" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'length(Reservations[].Instances[])' --output text)"
count "NAT gateways" "$(aws ec2 describe-nat-gateways --region "$region" \
  --filter "Name=state,Values=pending,available,deleting" --query 'length(NatGateways)' --output text)"
count "Elastic IPs" "$(aws ec2 describe-addresses --region "$region" --query 'length(Addresses)' --output text)"
count "VPC endpoints" "$(aws ec2 describe-vpc-endpoints --region "$region" \
  --filters "Name=tag:Project,Values=$name" --query 'length(VpcEndpoints)' --output text)"
count "Lab VPCs" "$(aws ec2 describe-vpcs --region "$region" --filters "Name=tag:Project,Values=$name" \
  --query 'length(Vpcs)' --output text)"
count "Lab ECR repositories" "$(aws ecr describe-repositories --region "$region" \
  --query "length(repositories[?starts_with(repositoryName, '$name')])" --output text)"
count "Lab S3 buckets" "$(aws s3api list-buckets --query "length(Buckets[?starts_with(Name, '$name-')])" --output text)"
count "Lab IAM roles" "$(aws iam list-roles --query "length(Roles[?starts_with(RoleName, '$name')])" --output text)"

exit $left
