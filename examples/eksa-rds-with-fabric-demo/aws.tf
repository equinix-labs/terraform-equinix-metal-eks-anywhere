module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-demo-vpc"
  cidr = "10.0.0.0/23"

  azs              = ["us-west-1b", "us-west-1c"]
  public_subnets   = ["10.0.0.0/25", "10.0.0.128/25"]
  database_subnets = ["10.0.1.0/25", "10.0.1.128/25"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = true

  tags = {
    Terraform = "true"
    Environment = "EKSADemo"
  }
}

resource "aws_vpn_gateway_route_propagation" "dx" {
  vpn_gateway_id = module.equinix-fabric-connection-aws.aws_vgw_id
  route_table_id = module.vpc.database_route_table_ids[0]
}

module "db" {
  source = "terraform-aws-modules/rds/aws"
  
  identifier = "eksademodbinstance"

  engine            = "mysql"
  engine_version    = "5.7"
  instance_class    = "db.t3.micro"
  allocated_storage = 5
  
  db_name  = "eksademodb"
  username = "eksademouser"
  port     = "3306"
  
  # DB security group
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  # DB subnet group
  db_subnet_group_name = module.vpc.database_subnet_group_name

  # DB parameter group
  family = "mysql5.7"

  # DB option group
  major_engine_version = "5.7"

  skip_final_snapshot = true
}

resource "aws_security_group_rule" "dbaccess" {
  type              = "ingress"
  from_port         = 0
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["169.254.0.0/16"]
  security_group_id = module.vpc.default_security_group_id
}