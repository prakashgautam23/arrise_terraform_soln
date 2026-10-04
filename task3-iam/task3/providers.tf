terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
    }
  }
}

# Account A (000000000000) - groups, users, roleA, roleB live here.
#
# In a real two-account setup, these two provider blocks would point at
# genuinely different credentials - e.g. a named profile per account, or one
# provider using default credentials and the other using an `assume_role`
# block to jump into Account B. For local plan/validate testing against a
# single sandbox account, both aliases simply use the default credential
# chain (whatever `aws sts get-caller-identity` resolves to) - there is only
# one real account available here, so both aliases resolve to it. This does
# not affect the correctness of the IAM/trust-policy design itself.
provider "aws" {
  alias  = "account_a"
  region = "us-east-1"
}

# Account B (111111111111) - roleC lives here.
provider "aws" {
  alias  = "account_b"
  region = "us-east-1"
}
