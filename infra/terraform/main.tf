data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.project_name
  tags = {
    Project = var.project_name
    Owner   = "cloud-infra-team"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "app_private" {
  count             = length(var.app_private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.app_private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name = "${local.name}-app-private-${count.index + 1}"
    Tier = "app-private"
  })
}

resource "aws_subnet" "data_private" {
  count             = length(var.data_private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name = "${local.name}-data-private-${count.index + 1}"
    Tier = "data-private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${local.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = "${local.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${local.name}-private-rt"
  })
}

resource "aws_route_table_association" "app_private" {
  count          = length(aws_subnet.app_private)
  subnet_id      = aws_subnet.app_private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data_private" {
  count          = length(aws_subnet.data_private)
  subnet_id      = aws_subnet.data_private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_security_group" "app" {
  name        = "${local.name}-burst-app-sg"
  description = "Allow application traffic from ALB only"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_security_group_rule" "alb_http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_to_app" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "app_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.app.id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "app_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.app.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = local.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ec2/${local.name}-burst-app"
  retention_in_days = 7

  tags = local.tags
}

resource "aws_iam_role" "app_ec2" {
  name               = "${local.name}-burst-app-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${local.name}-burst-app-ec2-profile"
  role = aws_iam_role.app_ec2.name
}

locals {
  app_environment_lines = join("\n", [
    for key, value in var.app_environment : "${key}=${value}"
  ])
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-burst-app-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.app_instance_type
  user_data = base64encode(templatefile("${path.module}/templates/burst-app-user-data.sh.tftpl", {
    app_container_name    = var.app_container_name
    app_environment_lines = local.app_environment_lines
    app_image             = var.app_image
    container_port        = var.container_port
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.app_ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.app_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = "${local.name}-burst-app"
      Role = "burst-app"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = "${local.name}-burst-app-volume"
      Role = "burst-app"
    })
  }

  tags = local.tags
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-burst-app-asg"
  min_size                  = var.app_min_size
  max_size                  = var.app_max_size
  desired_capacity          = var.app_desired_capacity
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.app.arn]
  vpc_zone_identifier       = aws_subnet.app_private[*].id

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-burst-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Owner"
    value               = local.tags.Owner
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.http]
}
