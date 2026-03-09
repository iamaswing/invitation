terraform {
  backend "s3" {
    bucket         = "um-terraform-state-bucket-ap-south-1"
    key            = "invitation/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Create the S3 bucket (private)
resource "aws_s3_bucket" "static_site" {
  bucket = "my-invitation-static-site-bucket"   # must be globally unique
  tags = {
    Name = "StaticSiteBucket"
  }
}

# Website configuration
resource "aws_s3_bucket_website_configuration" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Public access block (keep bucket private)
resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Identity (OAI) to access private bucket
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for static site"
}

# Bucket policy to allow CloudFront OAI to read objects
resource "aws_s3_bucket_policy" "cf_policy" {
  bucket = aws_s3_bucket.static_site.id

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_cloudfront_origin_access_identity.oai.iam_arn}"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.static_site.id}/*"
    }
  ]
}
EOT
}

# Request an ACM certificate (must be in us-east-1 for CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "s3-static-site"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static-site"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

    restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }
}

#Sync GitHub repo to S3
resource "null_resource" "sync_repo" {
  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/invitation
      git clone https://github.com/iamaswing/invitation.git /tmp/invitation
      aws s3 sync /tmp/invitation s3://${aws_s3_bucket.static_site.bucket}/ --delete
    EOT
  }

  depends_on = [aws_s3_bucket.static_site]
}
