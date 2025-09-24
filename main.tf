# Provider Configuration
# Specifies the AWS provider and region for Terraform to manage resources in.
provider "aws" {
  region = "us-east-1"
}

# VPC and Networking Resources
# Create a VPC, subnets, and related networking infrastructure for WordPress.

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "WordPress VPC"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPress Public Subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "WordPress Private Subnet"
  }
}

# Internet Gateway for Public Access
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPress Internet Gateway"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPress Public Route Table"
  }
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Groups
# Defines security groups to control access for EC2 and RDS instances.

# EC2 Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "wordpress_ec2_sg"
  description = "Security group for WordPress EC2 instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP access from anywhere
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH access from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name        = "wordpress_rds_sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]  # Allow MySQL access from EC2 instance
  }
}

# EC2 Instance
# Launches an EC2 instance for WordPress and sets up user data.

# AMI Data Source
data "aws_ami" "amazon_linux_2023" {
  most_recent = true    # Get the latest version of the AMI
  owners      = ["amazon"]  # Only accept Amazon-owned AMIs

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]  # Filter for Amazon Linux 2023 AMIs
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]  # Hardware Virtual Machine AMIs only
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]  # EBS-backed instances only
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]  # 64-bit x86 architecture only
  }
}

# WordPress EC2 Instance
resource "aws_instance" "wordpress_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id  # Use the AMI we filtered above
  instance_type          = "t2.micro"  # Free tier eligible instance type
  subnet_id              = aws_subnet.public_subnet.id  # Place in the public subnet
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]  # Attach the EC2 security group
  key_name               = "JC-AWS2024-KEY"  # Replace with your SSH key pair name

  # TODO: Pass in the 4 variables to the user data script
  user_data = "${file("wp_rds_install.sh")}"

  tags = {
    Name = "WordPress EC2 Instance"
  }
}

# RDS Database
# Set up a MySQL RDS instance for WordPress.

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]

  tags = {
    Name = "WordPress DB Subnet Group"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  identifier             = "wordpress-db"  # Unique identifier for the RDS instance
  allocated_storage      = 20              # 20GB of storage
  storage_type           = "gp2"           # General Purpose SSD
  engine                 = "mysql"         # MySQL database engine
  engine_version         = "8.0"           # MySQL version 8.0
  instance_class         = "db.t3.micro"   # Free tier eligible instance type
  db_name                = "wordpressdb"   # Name of the WordPress database
  username               = "admin"         # Database admin username
  password               = "Cyq716585!"  # Replace with a secure password
  parameter_group_name   = "default.mysql8.0"      # Default parameter group for MySQL 8.0
  skip_final_snapshot    = true                    # Skip final snapshot when destroying the database
  vpc_security_group_ids = [aws_security_group.rds_sg.id]  # Attach the RDS security group
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet_group.name  # Use the created subnet group
}

# Outputs
# Outputs the public IP of the EC2 instance and the RDS endpoint.

output "ec2_public_ip" {
  value = aws_instance.wordpress_ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

# Remote state backend in S3
terraform {
  backend "s3" {
    bucket  = "rit-jc-tfstate"              # <-- your bucket
    key     = "wordpress/terraform.tfstate"
    region  = "us-east-1"                   # <-- your region
    encrypt = true                   
  }
}
