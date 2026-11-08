#!/usr/bin/env bash
# Checks before the first apply of a session. Prints no account details, only whether they match.
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"

fail=0
check() { printf '%-48s %s\n' "$1" "$2"; }

for tool in terraform aws jq python3; do
  if command -v "$tool" >/dev/null; then check "$tool" "ok"; else check "$tool" "MISSING"; fail=1; fi
done

source_name="AWS profile ${AWS_PROFILE:-default}"
if [[ -n ${AWS_ACCESS_KEY_ID:-} ]]; then source_name="AWS credentials from the environment"; fi
if ! account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  check "$source_name" "NO CREDENTIALS (set them, or run aws configure --profile ipv6-lab)"
  exit 1
fi
check "$source_name" "ok"

tfvars="$TF_DIR/terraform.tfvars"
if [[ ! -f $tfvars ]]; then
  check "terraform.tfvars" "MISSING (copy terraform.tfvars.example)"
  fail=1
else
  wanted=$(sed -n 's/^allowed_account_id *= *"\([0-9]*\)".*/\1/p' "$tfvars")
  if [[ $account == "$wanted" ]]; then
    check "Credentials are for the lab account" "yes"
  else
    check "Credentials are for the lab account" "NO: stop here"
    fail=1
  fi
fi

region=$(lab_region)
check "Region" "$region"

if ! budgets=$(aws budgets describe-budgets --account-id "$account" --query 'length(Budgets)' --output text 2>/dev/null); then
  # Some accounts block the Budgets API, for example ones lent out for training; their owner's limits apply instead.
  check "AWS Budgets alert" "CAN'T CHECK (Budgets API denied)"
elif [[ $budgets =~ ^[1-9] ]]; then
  check "AWS Budgets alert" "ok ($budgets budget(s))"
else
  check "AWS Budgets alert" "NONE: create one first"
  fail=1
fi

offered=$(aws ec2 describe-instance-type-offerings --region "$region" --location-type availability-zone \
  --filters Name=instance-type,Values=t3.micro --query 'length(InstanceTypeOfferings)' --output text 2>/dev/null || echo 0)
check "Zones offering t3.micro" "$offered"

# Read-only calls can't show what a policy denies on create, so the first apply and destroy is the real test.
check "VPCs already in $region" "$(aws ec2 describe-vpcs --region "$region" --query 'length(Vpcs)' --output text)"
check "Elastic IPs already in $region" "$(aws ec2 describe-addresses --region "$region" --query 'length(Addresses)' --output text)"

exit $fail
