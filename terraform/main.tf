terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SSH key pair – upload your public key
resource "aws_key_pair" "deployer" {
  key_name   = "paperless-key"
  public_key = file(var.ssh_public_key_path)
}

# VPC and networking (simplest setup)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

# Security group – allow SSH (22), HTTP (80), HTTPS (443), and Paperless (8000 if needed)
resource "aws_security_group" "paperless_sg" {
  name        = "paperless-sg"
  description = "Allow SSH, HTTP, HTTPS, and Paperless port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: If Paperless runs on port 8000 behind reverse proxy, you might not need to open it.
  # If you want direct access for debugging, uncomment:
  # ingress {
  #   from_port = 8000
  #   to_port   = 8000
  #   protocol  = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paperless-sg"
  }
}

# EC2 instance – t2.micro (free tier)
resource "aws_instance" "paperless" {
  ami                    = var.ami_id  # Ubuntu 22.04 LTS (free tier eligible)
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.paperless_sg.id]
  subnet_id              = aws_subnet.main.id

  root_block_device {
    volume_size = 30  # Free tier includes 30GB EBS
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "paperless-portal"
  }

  # Optional: user_data script to install basic tools (Ansible will do the rest)
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip
    # Ansible will connect via SSH later
  EOF
}

# Elastic IP (optional, but good for a fixed IP even after reboot)
resource "aws_eip" "paperless_ip" {
  instance = aws_instance.paperless.id
  domain   = "vpc"

  tags = {
    Name = "paperless-eip"
  }
}

# Outputs
output "public_ip" {
  value = aws_eip.paperless_ip.public_ip
}

output "public_dns" {
  value = aws_instance.paperless.public_dns
}