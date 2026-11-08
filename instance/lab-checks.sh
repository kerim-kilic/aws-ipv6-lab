#!/usr/bin/env bash
# Runs on each lab instance from a systemd timer: what the instance can resolve and reach right now, written to one
# report, which goes to the console and to S3 over the dual-stack endpoint. Every check has a short timeout, because
# "connects, then hangs" is one of the results.
# Installed by user-data.sh.tftpl; settings come from /etc/lab-checks.env (BUCKET, PROBE_BUCKET, REGION, ROLE,
# ECR_REPO, REGISTRY_ID). ROLE=control skips the large downloads, so the NAT gateway's byte counts stay the client's.
set -uo pipefail

# shellcheck source=/dev/null
source /etc/lab-checks.env
export AWS_DEFAULT_REGION=$REGION AWS_MAX_ATTEMPTS=1 AWS_PAGER=""
ROLE=${ROLE:-client}
CLI_TIMEOUTS=(--cli-connect-timeout 5 --cli-read-timeout 10)

# Hosts with an A record only (at the time of writing) and hosts with an AAAA record too.
HOSTS=(
  github.com
  api.github.com
  pypi.org
  registry-1.docker.io
  "sts.$REGION.amazonaws.com"
  "sts.$REGION.api.aws"
  "s3.$REGION.amazonaws.com"
  "s3.dualstack.$REGION.amazonaws.com"
  "ssm.$REGION.amazonaws.com"
  "ssm.$REGION.api.aws"
  checkip.amazonaws.com
  api6.ipify.org
)

section() { printf '\n== %s\n' "$*"; }

# Prints the command, then its output and exit code, and how long it took.
run() {
  local start end rc
  printf '$ %s\n' "$*"
  start=$(date +%s%N)
  "$@" 2>&1
  rc=$?
  end=$(date +%s%N)
  printf '[exit %s, %d ms]\n' "$rc" $(((end - start) / 1000000))
}

# Instance metadata over IPv6 or IPv4. Prints nothing if that endpoint doesn't answer.
imds() {
  local base=$1 path=$2 token
  token=$(curl -sS --max-time 2 -X PUT "$base/latest/api/token" -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null) || return 1
  curl -sS --max-time 2 -H "X-aws-ec2-metadata-token: $token" "$base/latest/meta-data/$path" 2>/dev/null
}
IMDS6='http://[fd00:ec2::254]'
IMDS4='http://169.254.169.254'
meta() { imds "$IMDS6" "$1" || imds "$IMDS4" "$1"; }

# A and AAAA lookups through the system resolver, the way an application sees them.
lookup() {
  python3 - "$1" <<'PY'
import socket, sys
host = sys.argv[1]
for family, label in ((socket.AF_INET, "A"), (socket.AF_INET6, "AAAA")):
    try:
        found = sorted({ai[4][0] for ai in socket.getaddrinfo(host, 443, family, socket.SOCK_STREAM)})
        print(f"{host:40} {label:4} {' '.join(found)}")
    except socket.gaierror as e:
        print(f"{host:40} {label:4} - ({e.strerror})")
PY
}

# Downloads an S3 object and throws it away.
s3get() {
  aws s3 cp "${CLI_TIMEOUTS[@]}" --only-show-errors "$1" - >/dev/null
}
TEST_KEY=testdata/20mb.bin

https() {
  curl -sS -o /dev/null --connect-timeout 5 --max-time 15 \
    -w '%{http_code} via %{remote_ip}  dns=%{time_namelookup}s connect=%{time_connect}s total=%{time_total}s\n' \
    "https://$1/" 2>&1
}

# Six requests in a row and a git ls-remote: through NAT64, GitHub answered some requests and not others.
github() {
  local i
  for i in 1 2 3 4 5 6; do
    printf 'github.com #%s  ' "$i"
    curl -sS -o /dev/null --connect-timeout 5 --max-time 10 \
      -w '%{http_code} via %{remote_ip}  connect=%{time_connect}s total=%{time_total}s\n' https://github.com/ 2>&1
    sleep 2
  done
  run timeout 30 git ls-remote --heads https://github.com/kerim-kilic/eks-ipv4-lab
}

# Where the registry sends a client for the image's layer: ECR answers a blob request with a redirect to S3. Only the
# host is printed, because the rest of the redirect is a signed URL.
layer_redirect() {
  local registry=$1 digest location host
  digest=$(curl -sS --connect-timeout 5 --max-time 20 -u "AWS:$ECR_TOKEN" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://$registry/v2/$ECR_REPO/manifests/latest" |
    python3 -c 'import json, sys; print(max(json.load(sys.stdin)["layers"], key=lambda l: l["size"])["digest"])') ||
    return 1
  location=$(curl -sS -o /dev/null --connect-timeout 5 --max-time 20 -u "AWS:$ECR_TOKEN" -w '%{redirect_url}' \
    "https://$registry/v2/$ECR_REPO/blobs/$digest") || return 1
  host=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.urlsplit(sys.argv[1]).netloc)' "$location")
  echo "layer redirect to: $host"
  lookup "$host"
}

# A full docker pull, then the image and its layers are removed so the next pull downloads them again.
docker_pull() {
  local registry=$1 rc
  printf '%s' "$ECR_TOKEN" | docker login -u AWS --password-stdin "$registry" >/dev/null 2>&1
  timeout 120 docker pull -q "$registry/$ECR_REPO:latest"
  rc=$?
  docker image rm -f "$registry/$ECR_REPO:latest" >/dev/null 2>&1
  docker image prune -af >/dev/null 2>&1
  return $rc
}

step=$(meta tags/instance/LabStep || echo unknown)
name=$(meta tags/instance/Name || hostname)
ts=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p /var/lib/lab-checks
report=/var/lib/lab-checks/$ts.txt

{
  echo "step=$step instance=$name started=$ts"

  section "Instance"
  run cat /etc/amazon-linux-release
  run hostname -f
  run ip -brief address
  run ip -6 route
  run ip -4 route
  run cat /etc/resolv.conf
  run resolvectl dns

  section "Instance metadata"
  run curl -sS --max-time 2 -o /dev/null -w '%{http_code}\n' -X PUT "$IMDS6/latest/api/token" \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60'
  run curl -sS --max-time 2 -o /dev/null -w '%{http_code}\n' -X PUT "$IMDS4/latest/api/token" \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60'

  section "DNS"
  for host in "${HOSTS[@]}"; do lookup "$host"; done

  section "HTTPS"
  for host in "${HOSTS[@]}"; do printf '%-40s ' "$host"; https "$host"; done

  section "Address the internet sees"
  run curl -sS --max-time 10 https://api6.ipify.org
  run curl -sS --max-time 10 https://checkip.amazonaws.com

  section "GitHub"
  github

  section "AWS CLI, metadata endpoint as the SDK defaults it (IPv4)"
  run env AWS_USE_DUALSTACK_ENDPOINT=true aws sts get-caller-identity "${CLI_TIMEOUTS[@]}" --query Arn --output text

  section "AWS CLI, default endpoints (metadata over IPv6)"
  export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv6
  run aws sts get-caller-identity "${CLI_TIMEOUTS[@]}" --query Arn --output text
  run aws s3api list-objects-v2 "${CLI_TIMEOUTS[@]}" --bucket "$BUCKET" --max-items 1 --query 'KeyCount' --output text
  run aws ssm get-parameter "${CLI_TIMEOUTS[@]}" --output text --query Parameter.Name \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64

  section "AWS CLI, dual-stack endpoints (metadata over IPv6)"
  export AWS_USE_DUALSTACK_ENDPOINT=true
  run aws sts get-caller-identity "${CLI_TIMEOUTS[@]}" --query Arn --output text
  run aws s3api list-objects-v2 "${CLI_TIMEOUTS[@]}" --bucket "$BUCKET" --max-items 1 --query 'KeyCount' --output text
  run aws ssm get-parameter "${CLI_TIMEOUTS[@]}" --output text --query Parameter.Name \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
  unset AWS_USE_DUALSTACK_ENDPOINT

  if [[ $ROLE == client ]]; then
  # The probe bucket only allows reads through the S3 gateway endpoint once step 4 adds it, so a read that works there
  # went through the endpoint. The 20 MB download makes the NAT gateway's byte counts easy to attribute.
  section "S3 by name: probe object and a 20 MB download"
  lookup "$PROBE_BUCKET.s3.$REGION.amazonaws.com"
  lookup "$PROBE_BUCKET.s3.dualstack.$REGION.amazonaws.com"
  export AWS_USE_DUALSTACK_ENDPOINT=true
  if ! aws s3api head-object "${CLI_TIMEOUTS[@]}" --bucket "$BUCKET" --key "$TEST_KEY" >/dev/null 2>&1; then
    head -c 20971520 /dev/urandom >/var/lib/lab-checks/test.bin
    aws s3 cp "${CLI_TIMEOUTS[@]}" --only-show-errors /var/lib/lab-checks/test.bin "s3://$BUCKET/$TEST_KEY"
    rm -f /var/lib/lab-checks/test.bin
  fi
  unset AWS_USE_DUALSTACK_ENDPOINT
  echo "-- default endpoint"
  run aws s3api get-object "${CLI_TIMEOUTS[@]}" --bucket "$PROBE_BUCKET" --key probe.txt /dev/null \
    --query ContentLength --output text
  run s3get "s3://$BUCKET/$TEST_KEY"
  echo "-- dual-stack endpoint"
  export AWS_USE_DUALSTACK_ENDPOINT=true
  run aws s3api get-object "${CLI_TIMEOUTS[@]}" --bucket "$PROBE_BUCKET" --key probe.txt /dev/null \
    --query ContentLength --output text
  run s3get "s3://$BUCKET/$TEST_KEY"
  unset AWS_USE_DUALSTACK_ENDPOINT

  # Each pull starts more than a minute after the download before it, so the NAT gateway's per-minute byte counts
  # show each one on its own: 20 MB for the S3 download, 40 MB for an image pull that goes through NAT64.
  section "ECR: where the layers come from, and a 40 MB pull through each registry name"
  ECR_TOKEN=$(AWS_USE_DUALSTACK_ENDPOINT=true aws ecr get-login-password "${CLI_TIMEOUTS[@]}" 2>/dev/null)
  if [[ -z $ECR_TOKEN ]]; then
    echo "no ECR token"
  else
    for registry in "$REGISTRY_ID.dkr.ecr.$REGION.amazonaws.com" "$REGISTRY_ID.dkr-ecr.$REGION.on.aws"; do
      sleep 70
      echo "-- $registry  at $(date -u +%H:%M:%S)"
      lookup "$registry"
      layer_redirect "$registry" || echo "layer redirect: failed"
      run docker_pull "$registry"
    done
  fi
  unset ECR_TOKEN
  fi

  section "Packages and time"
  run timeout 120 dnf -q makecache --refresh
  run chronyc -n sources

  echo
  echo "finished=$(date -u +%Y%m%dT%H%M%SZ)"
} 2>&1 | tee "$report"

# Over the dual-stack endpoint, which needs nothing but IPv6 and the egress-only gateway. Fails on an instance that
# can't reach the metadata service over IPv6; its report is still on the console (aws ec2 get-console-output).
AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv6 AWS_USE_DUALSTACK_ENDPOINT=true \
  aws s3 cp "${CLI_TIMEOUTS[@]}" --only-show-errors "$report" "s3://$BUCKET/$step/$name/$ts.txt"
