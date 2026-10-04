variable "instances" {
  description = "Map of instance name => instance configuration. This single variable drives all 5 (or more) instances."
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    environment   = string
    owner         = string
    iops          = optional(number) # only required for io1 / io2 volumes
  }))
}

variable "critical_instance_name" {
  description = "Map key (instance name) that must be protected from accidental deletion via prevent_destroy."
  type        = string
}
