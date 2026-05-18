data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name = var.name_prefix

  haproxy_ami_id = var.haproxy_ami_id != "" ? var.haproxy_ami_id : data.aws_ami.al2023.id
  relay_ami_id   = var.relay_ami_id != "" ? var.relay_ami_id : data.aws_ami.al2023.id

  haproxy_user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf -y update || true
    dnf -y install haproxy || yum -y install haproxy

    cat > /etc/haproxy/haproxy.cfg <<'CFG'
    global
      log /dev/log local0

    defaults
      mode tcp
      timeout connect 5s
      timeout client  60s
      timeout server  60s

    frontend fe_tls
      bind *:443
      default_backend be_onprem_edge

    backend be_onprem_edge
      option tcp-check
    %{for b in var.onprem_edge_backends~}
      server ${replace(b, ":", "-")} ${b} check
    %{endfor~}
    CFG

    systemctl enable haproxy
    systemctl restart haproxy
  EOT

  relay_user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf -y update || true
    dnf -y install wireguard-tools || yum -y install wireguard-tools
    sysctl -w net.ipv4.ip_forward=1
  EOT
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-a"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_c_cidr
  availability_zone       = var.az_c
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-c"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nlb" {
  name   = "${local.name}-nlb-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "haproxy" {
  name   = "${local.name}-haproxy-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "haproxy_a" {
  ami                         = local.haproxy_ami_id
  instance_type               = var.haproxy_instance_type
  subnet_id                   = aws_subnet.public_a.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.haproxy.id]
  associate_public_ip_address = true
  user_data                   = local.haproxy_user_data

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-haproxy-a"
  }
}

resource "aws_instance" "haproxy_c" {
  ami                         = local.haproxy_ami_id
  instance_type               = var.haproxy_instance_type
  subnet_id                   = aws_subnet.public_c.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.haproxy.id]
  associate_public_ip_address = true
  user_data                   = local.haproxy_user_data

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-haproxy-c"
  }
}

resource "aws_lb" "nlb" {
  name               = "${local.name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_c.id]
  security_groups    = [aws_security_group.nlb.id]

  tags = {
    Name = "${local.name}-nlb"
  }
}

resource "aws_lb_target_group" "haproxy" {
  name        = "${local.name}-tg"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    protocol = "TCP"
    port     = "443"
  }
}

resource "aws_lb_target_group_attachment" "a" {
  target_group_arn = aws_lb_target_group.haproxy.arn
  target_id        = aws_instance.haproxy_a.id
  port             = 443
}

resource "aws_lb_target_group_attachment" "c" {
  target_group_arn = aws_lb_target_group.haproxy.arn
  target_id        = aws_instance.haproxy_c.id
  port             = 443
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.haproxy.arn
  }
}

resource "aws_security_group" "relay" {
  count  = var.create_wireguard_relay ? 1 : 0
  name   = "${local.name}-relay-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [var.relay_allowed_udp_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "relay" {
  count                       = var.create_wireguard_relay ? 1 : 0
  ami                         = local.relay_ami_id
  instance_type               = var.relay_instance_type
  subnet_id                   = aws_subnet.public_a.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.relay[0].id]
  associate_public_ip_address = true
  user_data                   = local.relay_user_data

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-relay"
  }
}

resource "aws_eip" "relay" {
  count    = var.create_wireguard_relay ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.relay[0].id
}

resource "aws_vpn_gateway" "this" {
  count           = var.create_site_to_site_vpn ? 1 : 0
  vpc_id          = aws_vpc.this.id
  amazon_side_asn = 64512

  tags = {
    Name = "${local.name}-vgw"
  }
}

resource "aws_customer_gateway" "this" {
  count      = var.create_site_to_site_vpn ? 1 : 0
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_public_ip
  type       = "ipsec.1"

  tags = {
    Name = "${local.name}-cgw"
  }
}

resource "aws_vpn_connection" "this" {
  count               = var.create_site_to_site_vpn ? 1 : 0
  customer_gateway_id = aws_customer_gateway.this[0].id
  vpn_gateway_id      = aws_vpn_gateway.this[0].id
  type                = "ipsec.1"
  static_routes_only  = var.vpn_static_routes_only

  tags = {
    Name = "${local.name}-vpn"
  }
}

resource "aws_vpn_connection_route" "onprem" {
  count                  = var.create_site_to_site_vpn && var.vpn_static_routes_only && var.onprem_cidr != "" ? 1 : 0
  destination_cidr_block = var.onprem_cidr
  vpn_connection_id      = aws_vpn_connection.this[0].id
}

resource "aws_route" "onprem" {
  count                  = var.create_site_to_site_vpn && var.onprem_cidr != "" ? 1 : 0
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.onprem_cidr
  gateway_id             = aws_vpn_gateway.this[0].id
}

resource "aws_route53_zone" "this" {
  count = var.create_route53_zone ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "app_alias" {
  count   = var.create_route53_zone && var.create_route53_alias_record ? 1 : 0
  zone_id = aws_route53_zone.this[0].zone_id
  name    = var.app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = false
  }
}
