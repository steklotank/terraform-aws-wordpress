terraform {
  # Объявляем нужне провайеры aws + tf
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
      }
    }
    required_version = ">= 1.2.0"
  } 
# Описываем провайдера aws в данном случае регион где будет размещено приложение
provider "aws" {
  region = "eu-north-1"
  }
# В качестве источника данных получаем default vpc чтобы потом на него сослаться
# data "aws_vpc" "default" {
#   default = true
#   }
# # Получаем id subnet из дефолтной vpc
# data "aws_subnets" "default" {
#   filter {
#     name = "vpc-id"
#     values = [data.aws_vpc.default.id]
#     }
#   } 


# Создаем VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}


# Создаем subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1a"  
}


# Новый gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Добавляем gateway к VPC
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Мапим таблицы маршрутизации к subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}



# Настройка фаервола, разрешаем порт 8080 и 22 берем из var разрешаем отовсюду
resource  "aws_security_group" "sg_wordpress"{
  name= "sg_wordpress"
  ingress{
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = var.cird_all
    }
  ingress{
    from_port = var.ssh_port
    to_port = var.ssh_port
    protocol = "tcp"
    cidr_blocks = var.cird_all
    }

  } 
# Main wordpress server configuration
resource "aws_launch_configuration" "wordpress_server" {
  image_id      = "ami-0914547665e6a707c"   
  instance_type = "t3.micro"
  security_groups = [aws_security_group.sg_wordpress.id]
  user_data = <<-EOF
  #!/bin/bash
  echo "hello, world" > index.html
  nohup busybox httpd -f -p ${var.server_port} &
  EOF
  key_name = "local_zenbook"
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
    }
  }

# Autoscaling group
resource "aws_autoscaling_group" "asg_wordpress_group" {
    launch_configuration = aws_launch_configuration.wordpress_server.name
     vpc_zone_identifier = [aws_subnet.public.id]

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = 2
    max_size = 5

    tag {
      key = "Name"
      value = "asg_wordpress_group"
      propagate_at_launch = true
    }  
}
#load balancing 
resource "aws_lb" "lb_wordpress" {
  name = "terraform-asg-wordpress"
  load_balancer_type = "application"
  subnets = [aws_subnet.public.id]
  security_groups = [aws_security_group.alb.id]
}
#load balancer default lisntener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.lb_wordpress.arn
  port = var.destination_port
  protocol = "HTTP"

  # По умолчанию возвращает простую страницу с кодом 404
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}
# Группа безопасности для ALB
resource "aws_security_group" "alb" {
  name = "terraform-wordpress-alb"
  # Разрешаем все входящие HTTP-запросы
  ingress {
    from_port = var.destination_port
    to_port = var.destination_port
    protocol = "tcp"
    cidr_blocks = var.cird_all
  }
  # Разрешаем все исходящие запросы
  egress {
    from_port = 0
    to_port = 0
    #ниже разрешаем все протоколы
    protocol = "-1"
    cidr_blocks = var.cird_all
  }
}
#
resource "aws_lb_target_group" "asg" {
  name = "asg-target-wordpress"
  port = var.destination_port
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  health_check {
    path = "/"
    protocol = "HTTP"
    port =  var.server_port
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}


resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.lb_wordpress.dns_name
  description = "The domain name of the load balancer"
}