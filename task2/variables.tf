variable "instances" {
  description = "Map of instance name => instance configuration. This single variable drives all 5 instances."
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    environment   = string
    owner         = string
    iops          = optional(number)
  }))
}

variable "critical_instance_name" {
  description = "Name (map key) of the instance protected from accidental deletion."
  type        = string
  default     = "critical-instance"
}
