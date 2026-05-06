data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_ec2" {
  name               = "${local.name}-db-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "db_ssm" {
  role       = aws_iam_role.db_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "db_ec2" {
  name = "${local.name}-db-ec2-profile"
  role = aws_iam_role.db_ec2.name
}

resource "aws_security_group" "proxysql" {
  name        = "${local.name}-proxysql-sg"
  description = "Allow DB client traffic from app runtime only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-proxysql-sg"
  })
}

resource "aws_security_group" "pxc" {
  name        = "${local.name}-pxc-sg"
  description = "Allow MySQL from ProxySQL and Galera traffic between PXC nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-pxc-sg"
  })
}

resource "aws_security_group" "proxysql_nlb" {
  count       = var.enable_proxysql_internal_nlb ? 1 : 0
  name        = "${local.name}-proxysql-nlb-sg"
  description = "Allow app runtime traffic to internal ProxySQL NLB"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-proxysql-nlb-sg"
  })
}

resource "aws_security_group_rule" "app_to_proxysql" {
  count                    = var.enable_proxysql_internal_nlb ? 0 : 1
  type                     = "egress"
  security_group_id        = aws_security_group.app.id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxysql.id
}

resource "aws_security_group_rule" "app_to_proxysql_nlb" {
  count                    = var.enable_proxysql_internal_nlb ? 1 : 0
  type                     = "egress"
  security_group_id        = aws_security_group.app.id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxysql_nlb[0].id
}

resource "aws_security_group_rule" "proxysql_from_app" {
  count                    = var.enable_proxysql_internal_nlb ? 0 : 1
  type                     = "ingress"
  security_group_id        = aws_security_group.proxysql.id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "proxysql_nlb_from_app" {
  count                    = var.enable_proxysql_internal_nlb ? 1 : 0
  type                     = "ingress"
  security_group_id        = aws_security_group.proxysql_nlb[0].id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "proxysql_nlb_to_proxysql" {
  count                    = var.enable_proxysql_internal_nlb ? 1 : 0
  type                     = "egress"
  security_group_id        = aws_security_group.proxysql_nlb[0].id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxysql.id
}

resource "aws_security_group_rule" "proxysql_from_nlb" {
  count                    = var.enable_proxysql_internal_nlb ? 1 : 0
  type                     = "ingress"
  security_group_id        = aws_security_group.proxysql.id
  from_port                = 6033
  to_port                  = 6033
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxysql_nlb[0].id
}

resource "aws_security_group_rule" "proxysql_to_pxc" {
  type                     = "egress"
  security_group_id        = aws_security_group.proxysql.id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.pxc.id
}

resource "aws_security_group_rule" "pxc_mysql_from_proxysql" {
  type                     = "ingress"
  security_group_id        = aws_security_group.pxc.id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxysql.id
}

resource "aws_security_group_rule" "pxc_galera_replication" {
  type              = "ingress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4567
  to_port           = 4567
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "pxc_galera_replication_out" {
  type              = "egress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4567
  to_port           = 4567
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "pxc_galera_replication_udp" {
  type              = "ingress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4567
  to_port           = 4567
  protocol          = "udp"
  self              = true
}

resource "aws_security_group_rule" "pxc_galera_replication_udp_out" {
  type              = "egress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4567
  to_port           = 4567
  protocol          = "udp"
  self              = true
}

resource "aws_security_group_rule" "pxc_ist" {
  type              = "ingress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4568
  to_port           = 4568
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "pxc_ist_out" {
  type              = "egress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4568
  to_port           = 4568
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "pxc_sst" {
  type              = "ingress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4444
  to_port           = 4444
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "pxc_sst_out" {
  type              = "egress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 4444
  to_port           = 4444
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "db_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.pxc.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "proxysql_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.proxysql.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_instance" "pxc" {
  count                       = var.db_node_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.data_private[count.index % length(aws_subnet.data_private)].id
  vpc_security_group_ids      = [aws_security_group.pxc.id]
  iam_instance_profile        = aws_iam_instance_profile.db_ec2.name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.db_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${local.name}-pxc-${count.index + 1}"
    Role = "pxc"
  })
}

resource "aws_instance" "proxysql" {
  count                       = var.proxysql_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.proxysql_instance_type
  subnet_id                   = aws_subnet.data_private[count.index % length(aws_subnet.data_private)].id
  vpc_security_group_ids      = [aws_security_group.proxysql.id]
  iam_instance_profile        = aws_iam_instance_profile.db_ec2.name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${local.name}-proxysql-${count.index + 1}"
    Role = "proxysql"
  })
}

resource "aws_lb" "proxysql_internal" {
  count              = var.enable_proxysql_internal_nlb ? 1 : 0
  name               = "${local.name}-proxysql-nlb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.proxysql_nlb[0].id]
  subnets            = aws_subnet.data_private[*].id

  tags = merge(local.tags, {
    Name = "${local.name}-proxysql-nlb"
  })
}

resource "aws_lb_target_group" "proxysql" {
  count       = var.enable_proxysql_internal_nlb ? 1 : 0
  name        = "${local.name}-proxysql-tg"
  port        = 6033
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "6033"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, {
    Name = "${local.name}-proxysql-tg"
  })
}

resource "aws_lb_listener" "proxysql" {
  count             = var.enable_proxysql_internal_nlb ? 1 : 0
  load_balancer_arn = aws_lb.proxysql_internal[0].arn
  port              = 6033
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxysql[0].arn
  }
}

resource "aws_lb_target_group_attachment" "proxysql" {
  count            = var.enable_proxysql_internal_nlb ? var.proxysql_count : 0
  target_group_arn = aws_lb_target_group.proxysql[0].arn
  target_id        = aws_instance.proxysql[count.index].id
  port             = 6033
}
