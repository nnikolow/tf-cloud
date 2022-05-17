terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.16.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.64.0"

  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, 2)
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, 2)

  enable_nat_gateway = true
  enable_vpn_gateway = false
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "nn-WebServers-SecGroup"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "nn-LoadBalancer-SecGroup"
  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "2.4.0"
  name = "nn-LoadBalancer"

  internal = false

  security_groups = [module.lb_security_group.this_security_group_id]
  subnets         = module.vpc.public_subnets

  number_of_instances = length(module.ec2_instances.instance_ids)
  instances           = module.ec2_instances.instance_ids

  listener = [{
    instance_port     = "80"
    instance_protocol = "HTTP"
    lb_port           = "80"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

module "ec2_instances" {
  source = "./modules/aws-instance"

  instance_count     = var.instances_per_subnet * length(module.vpc.private_subnets)
  instance_type      = var.instance_type
  subnet_ids         = module.vpc.private_subnets[*]
  security_group_ids = [module.app_security_group.this_security_group_id]
}

resource "aws_db_subnet_group" "private" {
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "database" {
  #test
  allocated_storage = 5
  engine            = "mysql"
  instance_class    = "db.t2.micro"
  username          = var.db_username
  password          = var.db_password

  db_subnet_group_name = aws_db_subnet_group.private.name

  skip_final_snapshot = true
}
