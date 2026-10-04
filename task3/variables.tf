variable "account_a_id" {
  description = "Account A - 12 digit account ID"
  type        = string
  default     = "000000000000"
}

variable "account_b_id" {
  description = "Account B - 12 digit account ID"
  type        = string
  default     = "111111111111"
}

variable "target_bucket_name" {
  description = "The single named S3 bucket roleC (Account B) gets full access to"
  type        = string
  default     = "arrise-assignment-shared-bucket"
}
