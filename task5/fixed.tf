variable "target_bucket_name" {
  type    = string
  default = "my-named-bucket" # the single bucket roleC is scoped to
}

# BUG 1 FIX: the principal must reference roleB as a ROLE, not a USER.
# Original:  arn:aws:iam::000000000000:user/roleB
# Fixed:     arn:aws:iam::000000000000:role/roleB
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:role/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

# BUG 2 FIX: scope the permissions policy to the one named bucket instead of
# every bucket in the account. Both the bucket ARN itself (for bucket-level
# actions like ListBucket) and bucket/* (for object-level actions like
# GetObject/PutObject) are included, since "full access to a bucket" needs
# both.
resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:*"
      Resource = [
        "arn:aws:s3:::${var.target_bucket_name}",
        "arn:aws:s3:::${var.target_bucket_name}/*"
      ]
    }]
  })
}
