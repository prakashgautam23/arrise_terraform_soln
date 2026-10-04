output "instance_ids" {
  description = "Map of instance name => instance ID"
  value       = module.ec2_fleet.instance_ids
}

output "private_ips" {
  description = "Map of instance name => private IP"
  value       = module.ec2_fleet.private_ips
}
