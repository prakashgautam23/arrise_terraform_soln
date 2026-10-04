instances = {
  dev-instance = {
    instance_type = "t2.micro"
    volume_type   = "gp2"
    volume_size   = 8
    environment   = "dev"
    owner         = "gautam"
  }
  test-instance = {
    instance_type = "t2.small"
    volume_type   = "gp3"
    volume_size   = 10
    environment   = "test"
    owner         = "gautam"
  }
  stage-instance = {
    instance_type = "t3.micro"
    volume_type   = "io1"
    volume_size   = 20
    iops          = 100
    environment   = "stage"
    owner         = "gautam"
  }
  prod-instance = {
    instance_type = "t3.small"
    volume_type   = "gp2"
    volume_size   = 30
    environment   = "prod"
    owner         = "gautam"
  }
  critical-instance = {
    instance_type = "t2.medium"
    volume_type   = "gp3"
    volume_size   = 40
    environment   = "prod"
    owner         = "gautam"
  }
}

critical_instance_name = "critical-instance"
