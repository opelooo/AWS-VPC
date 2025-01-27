provider "aws" {
  region = "ap-southeast-1" # singapore 1, sydney 2# Ganti dengan region Anda
}

# 1. Create VPC dengan Subnet Public/Privat
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

# 2. Security Groups
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

# 3. Application Load Balancer
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

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
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

# 4. Launch Template & Auto Scaling
# auto scaling template
resource "aws_launch_template" "web_lt" {
  name                   = "web-lt"
  image_id               = "ami-0c55b159cbfafe1f0" # Ganti dengan AMI yang sesuai
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webserver_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "OK" > /var/www/html/health
              EOF
              )
}

resource "aws_launch_template" "app_lt" {
  name                   = "app-lt"
  image_id               = "ami-0c55b159cbfafe1f0" # Ganti dengan AMI yang sesuai
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.appserver_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "OK" > /var/www/html/health
              EOF
              )
}

# auto_scaling_group
resource "aws_autoscaling_group" "web_asg" {
  name                = "web-asg"
  min_size            = 2  # Minimal 2 instance (1 per AZ)
  max_size            = 2  # Maksimal 2 instance (1 per AZ)
  desired_capacity    = 2  # Target 2 instance (1 per AZ)
  vpc_zone_identifier = module.vpc.public_subnets  # Pastikan subnet publik ada di 2 AZ

  availability_zones        = ["ap-south-1a", "ap-south-1b"]  # Ganti dengan AZ Anda

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web_tg.arn]

  # Opsional: Tambahkan tag untuk identifikasi
  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }

  # Pastikan instance baru dibuat di AZ yang kurang instance
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "app-asg"
  min_size            = 2  # Minimal 2 instance (1 per AZ)
  max_size            = 2  # Maksimal 2 instance (1 per AZ)
  desired_capacity    = 2  # Target 2 instance (1 per AZ)
  vpc_zone_identifier = module.vpc.private_subnets  # Pastikan subnet publik ada di 2 AZ

  availability_zones        = ["ap-south-1a", "ap-south-1b"]  # Ganti dengan AZ Anda

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  # Opsional: Tambahkan tag untuk identifikasi
  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }

  # Pastikan instance baru dibuat di AZ yang kurang instance
  lifecycle {
    create_before_destroy = true
  }
}

# 5. Route Table Associations (Private Subnets)
resource "aws_route_table_association" "private" {
  count          = length(module.vpc.private_subnets)
  subnet_id      = element(module.vpc.private_subnets, count.index)
  route_table_id = module.vpc.private_route_table_ids[0]
}