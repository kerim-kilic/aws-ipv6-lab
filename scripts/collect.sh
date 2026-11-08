#!/usr/bin/env bash
# Run after each apply. Saves the VPC settings for the current step, waits for every instance to upload a report from a
# check run that started after this script did, and saves the reports, the console output and the NAT gateway metrics.
# Everything goes to captures/raw/<step>/.
# Usage: scripts/collect.sh [minutes to wait, default 10]
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"

wait_minutes=${1:-14}
since=$(date -u +%Y%m%dT%H%M%SZ)
step=$(tf_out step)
region=$(tf_out aws_region)
vpc=$(tf_out vpc_id)
bucket=$(tf_out results_bucket)
read -r -a names <<<"$(tf_out instance_names)"
read -r -a ids <<<"$(tf_out instance_ids)"
out="$RAW_DIR/$step"
mkdir -p "$out/vpc" "$out/reports" "$out/console"

log "Step $step: saving the VPC settings"
aws ec2 describe-subnets --region "$region" --filters "Name=vpc-id,Values=$vpc" \
  --query 'Subnets[].{Name: Tags[?Key==`Name`]|[0].Value, Zone: AvailabilityZone, IPv4: CidrBlock, IPv6: Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock, Ipv6Native: Ipv6Native, Dns64: EnableDns64, Hostnames: PrivateDnsNameOptionsOnLaunch.HostnameType}' \
  --output table >"$out/vpc/subnets.txt"
aws ec2 describe-route-tables --region "$region" --filters "Name=vpc-id,Values=$vpc" \
  --query 'RouteTables[].{Name: Tags[?Key==`Name`]|[0].Value, Routes: join(`; `, Routes[].join(` -> `, [DestinationCidrBlock || DestinationIpv6CidrBlock || DestinationPrefixListId || ``, GatewayId || NatGatewayId || EgressOnlyInternetGatewayId || `?`]))}' \
  --output table >"$out/vpc/route-tables.txt"
aws ec2 describe-instances --region "$region" --instance-ids "${ids[@]}" \
  --query 'Reservations[].Instances[].{Name: Tags[?Key==`Name`]|[0].Value, Type: InstanceType, IPv4: PrivateIpAddress, IPv6: NetworkInterfaces[0].Ipv6Addresses[0].Ipv6Address, Hostname: PrivateDnsName, ImdsIPv6: MetadataOptions.HttpProtocolIpv6, ImdsTags: MetadataOptions.InstanceMetadataTags}' \
  --output table >"$out/vpc/instances.txt"

log "Waiting up to $wait_minutes minutes for a report started after $since from: ${names[*]}"
deadline=$((SECONDS + wait_minutes * 60))
pending=("${names[@]}")
while ((${#pending[@]})) && ((SECONDS < deadline)); do
  still=()
  for name in "${pending[@]}"; do
    key=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix "$step/$name/" --query 'Contents[].Key' --output text 2>/dev/null |
      tr '\t' '\n' | awk -F/ -v since="$since" '$NF > since".txt"' | sort | tail -n 1)
    if [[ -n $key && $key != None ]]; then
      aws s3 cp --only-show-errors "s3://$bucket/$key" "$out/reports/$name-${key##*/}"
      log "Saved $name-${key##*/}"
    else
      still+=("$name")
    fi
  done
  pending=("${still[@]+"${still[@]}"}")
  if ((${#pending[@]})); then sleep 20; fi
done
if ((${#pending[@]})); then
  log "No report in S3 from: ${pending[*]} (expected for an instance that can't reach the metadata service over IPv6)"
fi

# The console has the same report, also from instances that couldn't upload theirs. EC2 keeps the last 64 KB.
for i in "${!ids[@]}"; do
  aws ec2 get-console-output --region "$region" --instance-id "${ids[$i]}" --latest --output text \
    --query Output >"$out/console/${names[$i]}.txt" 2>/dev/null || true
done

# What went through NAT64, in 1-minute sums over the last hour. CloudWatch lags a few minutes behind.
nat=$(tf_out nat_gateway_id)
for metric in BytesOutToDestination BytesInFromDestination ConnectionAttemptCount ActiveConnectionCount; do
  echo "== $metric"
  aws cloudwatch get-metric-statistics --region "$region" --namespace AWS/NATGateway --metric-name "$metric" \
    --dimensions "Name=NatGatewayId,Value=$nat" --statistics Sum --period 60 \
    --start-time "$(date -u -d '-60 min' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --query 'sort_by(Datapoints, &Timestamp)[].[Timestamp, Sum]' --output text || true
done >"$out/nat-gateway-metrics.txt" 2>&1

log "Saved to ${out#"$REPO_ROOT"/}"
if ((${#pending[@]})); then exit 3; fi
