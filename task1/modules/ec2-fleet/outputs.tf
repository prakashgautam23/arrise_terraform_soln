output "instance_ids" {
  description = "Map of instance name => instance ID"
  value = merge(
    { (var.critical_instance_name) = aws_instance.critical.id },
    { for name, inst in aws_instance.ec2 : name => inst.id }
  )
}

output "private_ips" {
  description = "Map of instance name => private IP"
  value = merge(
    { (var.critical_instance_name) = aws_instance.critical.private_ip },
    { for name, inst in aws_instance.ec2 : name => inst.private_ip }
  )
}
