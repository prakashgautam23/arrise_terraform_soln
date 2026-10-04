# One-time bootstrap config. This creates the S3 bucket and DynamoDB table that
# the main task1/ config's backend.tf points at. It is run BEFORE task1 is ever
# initialized with its S3 backend, and it intentionally uses local state itself -
# a backend's own storage can't be created by the config that depends on it.
#
# Run this once:
#   cd bootstrap && terraform init && terraform apply
# Then go back to task1/ root, add backend.tf, and run `terraform init` again
# (Terraform will offer to migrate the existing local state into S3 - say yes).

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "gautam-devops-assign-tfstate-905418290018" # must be globally unique

  # Belt-and-braces: even with versioning + a lock table, protect the bucket
  # itself from being destroyed by an errant `terraform destroy` on this config.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning means a corrupted or accidentally-overwritten state file can be
# rolled back to a previous version instead of being lost outright.
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State files can contain sensitive data (ARNs, sometimes secrets pulled into
# resource attributes), so encrypt at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State should never be publicly reachable.
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table used for state locking. Terraform's S3 backend requires the
# partition key to be named exactly "LockID" (string) - this is a hard
# requirement, not a naming choice.
resource "aws_dynamodb_table" "tf_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for a lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
