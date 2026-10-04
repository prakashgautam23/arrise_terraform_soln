# Backend configuration must live in the root module - Terraform does not allow
# backend blocks inside child modules (modules/ec2-fleet/ cannot have one).
#
# Also important: backend blocks cannot reference variables, locals, or any
# other interpolation - every value here must be a literal. This is a Terraform
# limitation: the backend has to be resolved before the rest of the config (and
# therefore variables) is even parsed.
#
# Bucket and table below must already exist - created by bootstrap/ first.
terraform {
  backend "s3" {
    bucket         = "gautam-devops-assign-tfstate-905418290018"
    key            = "task2/ec2-fleet/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
