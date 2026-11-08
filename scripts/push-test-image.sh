#!/usr/bin/env bash
# Builds the test image (one layer of 40 MB of random data, which doesn't compress) and pushes it to the lab's ECR
# repository. Run once after the first apply. Needs Docker.
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"

repo=$(tf_out ecr_repository_url)
region=$(tf_out aws_region)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

head -c 41943040 /dev/urandom >"$build/blob.bin"
printf 'FROM scratch\nCOPY blob.bin /blob.bin\n' >"$build/Dockerfile"
# No provenance attestation: it would turn the tag into an index of two manifests instead of one image.
docker build -q --provenance=false --sbom=false -t "$repo:latest" "$build" >/dev/null

# The password goes straight from the AWS CLI to Docker, never to the terminal.
aws ecr get-login-password --region "$region" | docker login -u AWS --password-stdin "${repo%%/*}" >/dev/null
docker push -q "$repo:latest" >/dev/null
docker logout "${repo%%/*}" >/dev/null
docker image rm "$repo:latest" >/dev/null
log "Pushed the test image ($(aws ecr describe-images --region "$region" --repository-name "${repo#*/}" \
  --image-ids imageTag=latest --query 'imageDetails[0].[imageSizeInBytes, imageManifestMediaType]' --output text))"
