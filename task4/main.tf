# Least-privilege policy for the `ci` user (created in Task 3's account-a.tf,
# member of group1). Attached directly to the user rather than relying on
# group1's placeholder policy, since this is scoped specifically to what a
# CI pipeline needs - see NOTES.md for what was deliberately left out.

data "aws_iam_policy_document" "ci_least_privilege" {
  statement {
    sid       = "ECRAuthTokenAccountWide"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # AWS does not support resource-level scoping for this action
  }

  statement {
    sid    = "ECRPushToOneRepoOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.ecr_repository_name}"
    ]
  }

  statement {
    sid       = "ECSRegisterTaskDefinitionAccountWide"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"] # AWS does not support resource-level scoping for this action
  }

  statement {
    sid     = "ECSDescribeOneTaskFamily"
    effect  = "Allow"
    actions = ["ecs:DescribeTaskDefinition"]
    resources = [
      "arn:aws:ecs:${var.region}:${var.account_id}:task-definition/${var.ecs_task_family}:*"
    ]
  }

  statement {
    sid    = "ECSDeployToOneServiceOnly"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [
      "arn:aws:ecs:${var.region}:${var.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
    ]
  }

  statement {
    sid       = "PassOnlyTheTwoTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadOnlyBuildArtifactsBucketListing"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.build_artifacts_bucket}"]
  }

  statement {
    sid       = "ReadOnlyBuildArtifactsObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.build_artifacts_bucket}/*"]
  }
}

resource "aws_iam_user_policy" "ci_least_privilege" {
  name   = "ci-least-privilege"
  user   = "ci" # the aws_iam_user.ci created in Task 3's account-a.tf
  policy = data.aws_iam_policy_document.ci_least_privilege.json
}
