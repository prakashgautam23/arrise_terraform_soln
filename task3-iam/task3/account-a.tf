# =============================================================================
# group1: CLI / programmatic-only access.
#
# IAM has no policy action that "blocks console access" - console access is
# simply gated by whether a user has a login profile (password). So the
# control here is deliberate: no aws_iam_user_login_profile resource is
# created for engine or ci, meaning no console password exists for them at
# all. They can still have access keys for CLI/API use (see NOTES.md Q1 for
# why I would NOT actually hand out long-lived keys in real production).
# =============================================================================

resource "aws_iam_group" "group1" {
  provider = aws.account_a
  name     = "group1-programmatic"
}

resource "aws_iam_user" "engine" {
  provider = aws.account_a
  name     = "engine"
}

resource "aws_iam_user" "ci" {
  provider = aws.account_a
  name     = "ci"
}

resource "aws_iam_user_group_membership" "group1_members" {
  provider = aws.account_a
  for_each = toset(["engine", "ci"])
  user     = each.key
  groups   = [aws_iam_group.group1.name]

  depends_on = [aws_iam_user.engine, aws_iam_user.ci]
}

# Illustrative policy - the task specifies the ACCESS TYPE (programmatic-only),
# not the exact permission scope, so this is a stand-in. Replace with whatever
# engine/ci actually need to do in a real environment.
resource "aws_iam_group_policy" "group1_policy" {
  provider = aws.account_a
  name     = "group1-example-policy"
  group    = aws_iam_group.group1.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:Describe*", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}

# =============================================================================
# group2: full console + CLI access.
#
# Members get a real login profile (console password) in addition to being
# able to use access keys for CLI.
# =============================================================================

resource "aws_iam_group" "group2" {
  provider = aws.account_a
  name     = "group2-full-access"
}

resource "aws_iam_user" "alice" {
  provider = aws.account_a
  name     = "alice"
}

resource "aws_iam_user" "bob" {
  provider = aws.account_a
  name     = "bob"
}

resource "aws_iam_user_login_profile" "alice" {
  provider                = aws.account_a
  user                    = aws_iam_user.alice.name
  password_reset_required = true
}

resource "aws_iam_user_login_profile" "bob" {
  provider                = aws.account_a
  user                    = aws_iam_user.bob.name
  password_reset_required = true
}

resource "aws_iam_user_group_membership" "group2_members" {
  provider = aws.account_a
  for_each = toset(["alice", "bob"])
  user     = each.key
  groups   = [aws_iam_group.group2.name]

  depends_on = [aws_iam_user.alice, aws_iam_user.bob]
}

resource "aws_iam_group_policy_attachment" "group2_poweruser" {
  provider   = aws.account_a
  group      = aws_iam_group.group2.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# =============================================================================
# roleA: administrative access to all AWS services EXCEPT IAM.
# Allow "*" on everything, then an explicit Deny on iam:* in the same policy -
# Deny always wins over Allow when they're evaluated together.
# =============================================================================

data "aws_iam_policy_document" "roleA_trust" {
  provider = aws.account_a
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:root"]
    }
  }
}

resource "aws_iam_role" "roleA" {
  provider           = aws.account_a
  name               = "roleA-admin-except-iam"
  assume_role_policy = data.aws_iam_policy_document.roleA_trust.json
}

resource "aws_iam_role_policy" "roleA_policy" {
  provider = aws.account_a
  name     = "admin-except-iam"
  role     = aws_iam_role.roleA.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverything"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Sid      = "DenyIAM"
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# roleB: the ONLY permission is to assume roleC in Account B. Nothing else is
# attached - deliberately minimal, matching the task's "only permission" wording.
# =============================================================================

data "aws_iam_policy_document" "roleB_trust" {
  provider = aws.account_a
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:root"]
    }
  }
}

resource "aws_iam_role" "roleB" {
  provider           = aws.account_a
  name               = "roleB-cross-account-bridge"
  assume_role_policy = data.aws_iam_policy_document.roleB_trust.json
}

resource "aws_iam_role_policy" "roleB_policy" {
  provider = aws.account_a
  name     = "assume-roleC-only"
  role     = aws_iam_role.roleB.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeRoleCOnly"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.account_b_id}:role/roleC"
    }]
  })
}
