# A private repository with one test image (scripts/push-test-image.sh): a single layer of 40 MB of random data, so a
# pull shows up clearly in the NAT gateway's byte counts.
# Accepted for a short-lived lab (see the README's "Shortcuts taken"): the only image is random test data, pushed again
# under the same tag, so no scanning, mutable tags and the default encryption.
#trivy:ignore:AWS-0030
#trivy:ignore:AWS-0031
#trivy:ignore:AWS-0033
resource "aws_ecr_repository" "test" {
  name                 = "${var.name}-test"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}
