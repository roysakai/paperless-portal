variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 22.04 LTS (free tier)"
  # Find the latest Ubuntu 22.04 AMI ID for your region
  # For us-east-1, as of 2026: ami-0c7217fde7d3a7f8a (example – check AWS console)
  default = "ami-0c7217fde7d3a7f8a"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key (e.g., ~/.ssh/id_rsa.pub)"
  default     = "~/.ssh/id_rsa.pub"
}