module "ec2_fleet" {
  source = "./modules/ec2-fleet"

  instances               = var.instances
  critical_instance_name  = var.critical_instance_name
}
