# The instances upload their check results here over S3's dual-stack endpoint, which has an IPv6 address and so works
# with nothing but the egress-only internet gateway. That way the results arrive even in the steps where NAT64 doesn't.
resource "aws_s3_bucket" "results" {
  bucket_prefix = "${var.name}-results-"
  force_destroy = true # results are copied to captures/raw before the destroy
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# A small object the checks read through each S3 name. In step 4 its bucket policy shows which route a request took.
resource "aws_s3_bucket" "probe" {
  bucket_prefix = "${var.name}-probe-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "probe" {
  bucket                  = aws_s3_bucket.probe.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "probe" {
  bucket = aws_s3_bucket.probe.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_object" "probe" {
  bucket       = aws_s3_bucket.probe.id
  key          = "probe.txt"
  content      = "Read through the gateway endpoint.\n"
  content_type = "text/plain"
}
