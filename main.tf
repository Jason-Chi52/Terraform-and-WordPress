########################################
# Provider & Backend (S3 state)
########################################
terraform {
  backend "s3" {
    bucket = "rit-jc-tfstate"          # your bucket in us-east-1
    key    = "wordpress/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

########################################
# Variables (fixed: multi-line blocks)
########################################
variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpressdb"
}

########################################
# Networking
########################################
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "WordPress VPC" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "WordPress Public Subnet" }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "WordPress Private Subnet" }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags   = { Name = "WordPress Internet Gateway" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = { Name = "WordPress Public Route Table" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

########################################
# Security Groups
########################################
resource "aws_security_group" "ec2_sg" {
  name        = "wordpress_ec2_sg"
  description = "Security group for WordPress EC2 instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wordpress_ec2_sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "wordpress_rds_sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = { Name = "wordpress_rds_sg" }
}

########################################
# AMI (Amazon Linux 2023)
########################################
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter { name = "name"                values = ["al2023-ami-2023*"] }
  filter { name = "virtualization-type" values = ["hvm"] }
  filter { name = "root-device-type"    values = ["ebs"] }
  filter { name = "architecture"        values = ["x86_64"] }
}

########################################
# RDS
########################################
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  # (For class simplicity) one private + one public subnet
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]
  tags = { Name = "WordPress DB Subnet Group" }
}

resource "aws_db_instance" "wordpress_db" {
  identifier             = "wordpress-db"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet_group.name
  publicly_accessible    = false
  deletion_protection    = false
  tags = { Name = "WordPress RDS" }
}

########################################
# EC2 (WordPress) + user_data template
########################################
resource "aws_instance" "wordpress_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/wp_rds_install.sh.tftpl", {
    DB_NAME     = var.db_name
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
    DB_HOST     = aws_db_instance.wordpress_db.address
  })

  tags = { Name = "WordPress EC2 Instance" }
}

########################################
# Outputs
########################################
output "ec2_public_ip" {
  value       = aws_instance.wordpress_ec2.public_ip
  description = "Public IP of the WordPress EC2 instance"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.address
  description = "RDS endpoint hostname"
}
