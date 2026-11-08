# shellcheck shell=bash
# Sourced by the other scripts: shared settings and helpers.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$REPO_ROOT/terraform"
# shellcheck disable=SC2034 # read by the scripts that source this file
RAW_DIR="$REPO_ROOT/captures/raw"

# Credentials already in the environment win; otherwise use the lab profile. Setting AWS_PROFILE to a profile that
# doesn't exist makes the CLI fail even when the environment has credentials.
if [[ -z ${AWS_ACCESS_KEY_ID:-} ]]; then
  export AWS_PROFILE=${AWS_PROFILE:-ipv6-lab}
fi
export AWS_PAGER=""

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

# From terraform.tfvars, so it works before the first apply and after the destroy.
lab_region() {
  local region
  region=$(sed -n 's/^aws_region *= *"\(.*\)".*/\1/p' "$TF_DIR/terraform.tfvars" 2>/dev/null || true)
  echo "${region:-us-east-1}"
}

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}
