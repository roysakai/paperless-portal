terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SSH key pair
resource "random_id" "key_suffix" {
  byte_length = 4
}

resource "aws_key_pair" "deployer" {
  key_name   = "paperless-key-${random_id.key_suffix.hex}"
  public_key = file(var.ssh_public_key_path)
}

# IAM role for EC2 SSM access
resource "random_id" "role_suffix" {
  byte_length = 4
}

resource "aws_iam_role" "ssm_role" {
  name = "SSMRoleForEC2-${random_id.role_suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Create an instance profile for the role (required for EC2)
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "SSMInstanceProfile-${random_id.role_suffix.hex}"
  role = aws_iam_role.ssm_role.name
}

# Attach the SSM managed policy to the role
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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

  # For debugging, uncomment:
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
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.paperless_sg.id]
  subnet_id              = aws_subnet.main.id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  root_block_device {
    volume_size = 30  # Free tier includes 30GB EBS
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "paperless-portal"
  }

  # user_data script to install basic tools (Ansible will do the rest)
  user_data = <<-EOF
    #!/bin/bash
    set -e -x

    # Ensure SSH server is installed and running
    apt-get update -q
    apt-get install -y -q openssh-server
    systemctl enable --now ssh

    # Install SSM agent via snap (Ubuntu 22.04 default)
    snap install amazon-ssm-agent --classic
    # Snap services start automatically; no need to enable with systemctl

    # Add your public key (replace with actual key)
    mkdir -p /home/ubuntu/.ssh
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDURTeNHHLXKPtGKzz/XWDT+Mkigc53zyxkWhDlYkvxxnAn..........." >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh

    # Create 1GB swap file to avoid OOM kills
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Enable passwordless sudo (essential for Ansible)
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-ubuntu-users
    chmod 440 /etc/sudoers.d/90-ubuntu-users

    # Signal success
    touch /var/lib/cloud/instance/user-data.done
  EOF

}

# Elastic IP (for a fixed IP even after reboot)
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