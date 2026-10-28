# Use the default VPC to avoid NAT Gateway charges
data "aws_vpc" "default" {
  default = true
}

# Security Group to allow SSH, HTTP, Jenkins, and Kubernetes traffic
resource "aws_security_group" "devops_sg" {
  name        = "devops-free-tier-sg"
  description = "Allow SSH, HTTP, Jenkins, and K8s NodePort"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
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

# Fetch the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Generate an SSH key pair for you to connect to the instance
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "tf_key" {
  key_name   = "devops-key"
  public_key = tls_private_key.rsa.public_key_openssh
}

# Save the private key to your local machine
resource "local_file" "tf_key" {
  content         = tls_private_key.rsa.private_key_pem
  filename        = "devops-key.pem"
  file_permission = "0400"
}

# Create the Free Tier EC2 Instance
resource "aws_instance" "k8s_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro" # 100% Free Tier Eligible
  key_name      = aws_key_pair.tf_key.key_name
  vpc_security_group_ids = [aws_security_group.devops_sg.id]

  # Install Docker and K3s (Kubernetes) automatically on boot
  user_data = <<-EOF
              #!/bin/bash
              # Create a 2GB swap file to prevent out-of-memory errors on t2.micro
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

              # Install Docker
              apt-get update -y
              apt-get install -y docker.io
              usermod -aG docker ubuntu
              systemctl start docker
              systemctl enable docker

              # Install K3s (Lightweight Kubernetes)
              curl -sfL https://get.k3s.io | sh -
              chmod 644 /etc/rancher/k3s/k3s.yaml
              EOF

  tags = {
    Name = "DevOps-K8s-FreeTier"
  }
}

# Output the public IP so you can connect to it
output "server_public_ip" {
  value = aws_instance.k8s_server.public_ip
}
