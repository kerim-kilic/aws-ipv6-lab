# A private repository with one test image (scripts/push-test-image.sh): a single layer of 40 MB of random data, so a
# pull shows up clearly in the NAT gateway's byte counts.
resource "aws_ecr_repository" "test" {
  name                 = "${var.name}-test"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}
