terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region
}

# Ubuntu 24.04 LTS arm64 (kernel 6.x, in-tree wireguard, recent ENA driver)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "wg-saturate" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = var.az
  map_public_ip_on_launch = true
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

# Cluster placement group: 10 Gbps/flow, full bisection, low latency
resource "aws_placement_group" "this" {
  name     = "wg-saturate-cluster"
  strategy = "cluster"
}

resource "aws_security_group" "this" {
  name   = "wg-saturate"
  vpc_id = aws_vpc.this.id

  # SSH from operator
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }
  # All traffic between the two nodes (WireGuard UDP, iperf, nvme-tcp, etc.)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "node" {
  count                       = 2
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.this.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  placement_group             = aws_placement_group.this.id
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  # Spot by default (KICKOFF prefers it). On-Demand emits no market options at all.
  # one-time request + terminate-on-interruption: a simple, re-appliable matrix node.
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
        max_price                      = var.max_spot_price != "" ? var.max_spot_price : null
      }
    }
  }

  # ENA Express (SRD) is enabled out-of-band via scripts/enable-ena-express.sh so it can be
  # toggled on/off between measurement runs. The primary ENI id is exported below.

  tags = { Name = "wg-saturate-${count.index == 0 ? "a" : "b"}" }
}
