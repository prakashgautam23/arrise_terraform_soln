# Dynamic AMI lookup so the module isn't pinned to a region-specific hardcoded AMI ID.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# One keypair per instance. A fresh RSA key is generated per instance name so
# no real private key material has to be supplied or committed to the repo -
# this is acceptable for an assignment/demo module. In a real environment you
# would reference pre-existing key pairs (or, better, use SSM / EC2 Instance
# Connect and drop key pairs entirely).
resource "tls_private_key" "this" {
  for_each  = var.instances
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "this" {
  for_each   = var.instances
  key_name   = "${each.key}-key"
  public_key = tls_private_key.this[each.key].public_key_openssh
}

# The one instance that must survive an accidental `terraform destroy`.
# prevent_destroy must be a literal `true` - it cannot be made conditional
# inside a for_each block - so this instance is pulled out into its own
# resource block instead of looping over all 5 in one place.
resource "aws_instance" "critical" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instances[var.critical_instance_name].instance_type
  key_name      = aws_key_pair.this[var.critical_instance_name].key_name

  root_block_device {
    volume_type = var.instances[var.critical_instance_name].volume_type
    volume_size = var.instances[var.critical_instance_name].volume_size
    iops = contains(["io1", "io2"], var.instances[var.critical_instance_name].volume_type) ? (
      var.instances[var.critical_instance_name].iops
    ) : null
  }

  tags = {
    Name        = var.critical_instance_name
    Environment = var.instances[var.critical_instance_name].environment
    Owner       = var.instances[var.critical_instance_name].owner
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Every other instance, fully driven by the input map - no hardcoded blocks.
resource "aws_instance" "ec2" {
  for_each = { for name, cfg in var.instances : name => cfg if name != var.critical_instance_name }

  ami           = data.aws_ami.amazon_linux.id
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.this[each.key].key_name

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = contains(["io1", "io2"], each.value.volume_type) ? each.value.iops : null
  }

  tags = {
    Name        = each.key
    Environment = each.value.environment
    Owner       = each.value.owner
  }
}
