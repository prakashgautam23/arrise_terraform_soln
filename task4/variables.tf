variable "region" {
  type    = string
  default = "us-east-1"
}

variable "account_id" {
  description = "Account where the ECR repo / ECS cluster / S3 bucket live"
  type        = string
  default     = "000000000000"
}

variable "ecr_repository_name" {
  type    = string
  default = "my-app-repo"
}

variable "ecs_cluster_name" {
  type    = string
  default = "my-cluster"
}

variable "ecs_service_name" {
  type    = string
  default = "my-service"
}

variable "ecs_task_family" {
  description = "Task definition family name (revision is unknown ahead of a new deploy, so this is wildcarded as family:*)"
  type        = string
  default     = "my-app-family"
}

variable "task_execution_role_arn" {
  description = "The ECS task EXECUTION role (pulls image, writes logs) that RegisterTaskDefinition needs to pass"
  type        = string
  default     = "arn:aws:iam::000000000000:role/my-app-task-execution-role"
}

variable "task_role_arn" {
  description = "The ECS task ROLE (what the running container itself assumes) - may be the same as execution role in simple setups, kept separate here since that's the more common real-world shape"
  type        = string
  default     = "arn:aws:iam::000000000000:role/my-app-task-role"
}

variable "build_artifacts_bucket" {
  type    = string
  default = "my-build-artifacts-bucket"
}
