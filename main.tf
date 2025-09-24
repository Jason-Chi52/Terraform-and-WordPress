# ---------------- Provider ----------------
provider "aws" {
  region = "us-east-1"
}

# ---------------- Networking ----------------
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

# ---------------- Security Groups ----------------
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
}

# ---------------- AMI ----------------
# AMI Data Source (fix: multi-line filter blocks)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}


# ---------------- EC2 (WordPress) ----------------
resource "aws_instance" "wordpress_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = "JC-AWS2024-KEY"

  # Make sure this file exists in the same folder as main.tf
  user_data = templatefile("${path.module}/wp_rds_install.sh.tftpl", {
    DB_NAME     = "wordpressdb"
    DB_USER     = "admin"
    DB_PASSWORD = "Cyq716585!"                     # <-- use your real password / or a var
    DB_HOST     = aws_db_instance.wordpress_db.address
  })


# ---------------- RDS ----------------
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group_jc"  # unique name to avoid "AlreadyExists"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]
  tags       = { Name = "WordPress DB Subnet Group" }
}

resource "aws_db_instance" "wordpress_db" {
  identifier             = "wordpress-db-jc"       # unique identifier to avoid "AlreadyExists"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "wordpressdb"
  username               = "admin"
  password               = "Cyq716585!"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet_group.name
}

# ---------------- Outputs ----------------
output "ec2_public_ip" {
  value = aws_instance.wordpress_ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

# ---------------- Remote state backend (S3) ----------------
terraform {
  backend "s3" {
    bucket  = "rit-jc-tfstate"
    key     = "wordpress/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
