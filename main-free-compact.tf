/*
VPC Webserver
Network CIDR : 192.168.100.1/27
Subnet 1 : 192.168.100.0/28 
Subnet 2:  192.168.100.16/28

VPC ApiServer
Network CIDR: 172.31.0.1/27
Subnet 1 : 172.31.0.0/28
Subnet 2 : 172.31.0.16/28

region jakarta
*/
provider "aws" {
  region = "ap-southeast-3" # singapore 1, sydney 2, jakarta 3 # Ganti dengan region Anda
}

# Create VPC dengan Subnet Public dan Privat
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway     = false
  enable_vpn_gateway     = false

  tags = {
    Environment = "production"
  }
}

# Security Groups
# webserver_sg
resource "aws_security_group" "webserver_sg" {
  name        = "webserver-sg"
  description = "Public Web Server Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress = []
}

# appserver_sg
resource "aws_security_group" "appserver_sg" {
  name        = "appserver-sg"
  description = "App Server Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.webserver_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# database_sg
resource "aws_security_group" "database_sg" {
  name        = "database-sg"
  description = "Database Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.appserver_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
# load_balancer
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webserver_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
}

# load_balancer target group
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Route Table Associations (Private Subnets)
resource "aws_route_table_association" "private" {
  count          = length(module.vpc.private_subnets)
  subnet_id      = element(module.vpc.private_subnets, count.index)
  route_table_id = module.vpc.private_route_table_ids[0]
}