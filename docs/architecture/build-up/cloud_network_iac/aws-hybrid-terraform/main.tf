data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

locals {
  app_fqdn       = var.app_fqdn != "" ? var.app_fqdn : var.domain_name
  ec2_ami_id     = var.ec2_ami_id != "" ? var.ec2_ami_id : data.aws_ami.ubuntu_2204.id
  onprem_set     = toset(var.onprem_cidrs)
  private_rt_ids = [for rt in aws_route_table.private : rt.id]

  common_tags = {
    Project = var.name_prefix
    Managed = "terraform"
  }

  haproxy_user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y haproxy python3 amazon-ssm-agent

    mkdir -p /opt/health
    cat > /opt/health/healthz <<'HEALTH'
    ok
    HEALTH

    cat > /etc/systemd/system/health-http.service <<'UNIT'
    [Unit]
    Description=Simple local health endpoint
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/health
    ExecStart=/usr/bin/python3 -m http.server 8080
    Restart=always
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    UNIT

    cat > /etc/haproxy/haproxy.cfg <<'CFG'
    global
      log /dev/log local0

    defaults
      mode tcp
      timeout connect 5s
      timeout client  60s
      timeout server  60s

    frontend ft_http
      bind *:80
      default_backend bk_health

    frontend ft_tls_placeholder
      bind *:443
      default_backend bk_health

    backend bk_health
      server local 127.0.0.1:8080 check
    CFG

    systemctl daemon-reload
    systemctl enable --now health-http.service
    systemctl enable --now haproxy
    systemctl enable --now amazon-ssm-agent || true
  EOT
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-subnet-public-${each.key}-${each.value.az}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-subnet-private-${each.key}-${each.value.az}"
    Tier = "private"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eip-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rtb-public"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rtb-private-${each.key}"
  })
}

resource "aws_route" "private_default" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_rt_ids

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpce-s3"
  })
}

resource "aws_security_group" "nlb" {
  name        = "${var.name_prefix}-sg-nlb"
  description = "Allow public access to NLB listeners"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.nlb_ingress_cidrs
  }

  ingress {
    description = "HTTPS/TCP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.nlb_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sg-nlb"
  })
}

resource "aws_security_group" "haproxy" {
  name        = "${var.name_prefix}-sg-haproxy-private"
  description = "Private HAProxy targets"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "NLB to HAProxy HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description     = "NLB to HAProxy TCP 443"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  dynamic "ingress" {
    for_each = local.onprem_set

    content {
      description = "ICMP from on-prem ${ingress.value}"
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sg-haproxy-private"
  })
}

resource "aws_iam_role" "ssm_ec2" {
  name               = "${var.name_prefix}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ec2-ssm-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_ec2" {
  name = "${var.name_prefix}-ec2-ssm-profile"
  role = aws_iam_role.ssm_ec2.name
}

resource "aws_instance" "haproxy" {
  for_each = aws_subnet.private

  ami                         = local.ec2_ami_id
  instance_type               = var.ec2_instance_type
  subnet_id                   = each.value.id
  associate_public_ip_address = false
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  iam_instance_profile        = aws_iam_instance_profile.ssm_ec2.name
  vpc_security_group_ids      = [aws_security_group.haproxy.id]
  user_data                   = local.haproxy_user_data

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-haproxy-${each.key}"
  })

  depends_on = [aws_iam_role_policy_attachment.ssm_managed]
}

resource "aws_lb" "nlb" {
  name               = "${var.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  security_groups    = [aws_security_group.nlb.id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nlb"
  })
}

resource "aws_lb_target_group" "http" {
  name        = "${var.name_prefix}-tg-http"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled  = true
    protocol = "HTTP"
    path     = "/healthz"
    port     = "80"
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-tg-http"
  })
}

resource "aws_lb_target_group" "https" {
  name        = "${var.name_prefix}-tg-https"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "443"
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-tg-https"
  })
}

resource "aws_lb_target_group_attachment" "http" {
  for_each = aws_instance.haproxy

  target_group_arn = aws_lb_target_group.http.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "https" {
  for_each = aws_instance.haproxy

  target_group_arn = aws_lb_target_group.https.arn
  target_id        = each.value.id
  port             = 443
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

resource "aws_vpn_gateway" "this" {
  count = var.create_vpn ? 1 : 0

  amazon_side_asn = 64512

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vgw"
  })
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.create_vpn ? 1 : 0

  vpc_id         = aws_vpc.this.id
  vpn_gateway_id = aws_vpn_gateway.this[0].id
}

resource "aws_customer_gateway" "this" {
  count = var.create_vpn ? 1 : 0

  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-cgw"
  })
}

resource "aws_vpn_connection" "this" {
  count = var.create_vpn ? 1 : 0

  customer_gateway_id = aws_customer_gateway.this[0].id
  vpn_gateway_id      = aws_vpn_gateway.this[0].id
  type                = "ipsec.1"
  static_routes_only  = true

  tunnel1_ike_versions                 = ["ikev1"]
  tunnel1_phase1_dh_group_numbers      = [2]
  tunnel1_phase1_encryption_algorithms = ["AES128"]
  tunnel1_phase1_integrity_algorithms  = ["SHA1"]
  tunnel1_phase2_dh_group_numbers      = [2]
  tunnel1_phase2_encryption_algorithms = ["AES128"]
  tunnel1_phase2_integrity_algorithms  = ["SHA1"]

  tunnel2_ike_versions                 = ["ikev1"]
  tunnel2_phase1_dh_group_numbers      = [2]
  tunnel2_phase1_encryption_algorithms = ["AES128"]
  tunnel2_phase1_integrity_algorithms  = ["SHA1"]
  tunnel2_phase2_dh_group_numbers      = [2]
  tunnel2_phase2_encryption_algorithms = ["AES128"]
  tunnel2_phase2_integrity_algorithms  = ["SHA1"]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpn"
  })

  depends_on = [aws_vpn_gateway_attachment.this]
}

resource "aws_vpn_connection_route" "onprem" {
  for_each = var.create_vpn ? local.onprem_set : toset([])

  destination_cidr_block = each.value
  vpn_connection_id      = aws_vpn_connection.this[0].id
}

resource "aws_vpn_gateway_route_propagation" "private" {
  for_each = var.create_vpn ? aws_route_table.private : {}

  vpn_gateway_id = aws_vpn_gateway.this[0].id
  route_table_id = each.value.id

  depends_on = [aws_vpn_connection_route.onprem]
}

resource "aws_route53_zone" "this" {
  count = var.create_route53_zone ? 1 : 0

  name = var.domain_name

  tags = merge(local.common_tags, {
    Name = var.domain_name
  })
}

resource "aws_route53_record" "app_alias" {
  count = var.create_route53_zone && var.create_route53_alias_record ? 1 : 0

  zone_id = aws_route53_zone.this[0].zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = false
  }
}
