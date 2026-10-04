# =============================================================================
# roleC (Account B): full access to a single named S3 bucket, assumable ONLY
# by roleB in Account A - not by anything else in Account A.
#
# The trust policy names roleB's SPECIFIC role ARN, not Account A's root
# (arn:...:000000000000:root). This is deliberate - see NOTES.md Q2 for the
# full reasoning on why that distinction matters.
# =============================================================================

data "aws_iam_policy_document" "roleC_trust" {
  provider = aws.account_b
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:role/roleB-cross-account-bridge"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  provider           = aws.account_b
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3_access" {
  provider = aws.account_b
  name     = "roleC-s3-full-access-single-bucket"
  role     = aws_iam_role.roleC.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FullAccessSingleBucket"
      Effect = "Allow"
      Action = "s3:*"
      Resource = [
        "arn:aws:s3:::${var.target_bucket_name}",
        "arn:aws:s3:::${var.target_bucket_name}/*"
      ]
    }]
  })
}
