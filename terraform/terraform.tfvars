aws_region   = "eu-west-2"
project_name = "ha-webapp"
environment  = "prod"
key_name     = "ha3tier-key"

vpc_cidr                 = "10.0.0.0/16"
public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]

web_instance_type    = "t3.micro"
web_min_size         = 2
web_max_size         = 6
web_desired_capacity = 2

app_instance_type    = "t3.small"
app_min_size         = 2
app_max_size         = 6
app_desired_capacity = 2

db_instance_class = "db.t3.micro"
db_engine_version = "8.0"
db_name           = "appdb"
db_username       = "dbadmin"
db_multi_az       = true

certificate_arn = ""
domain_name     = ""
route53_zone_id = ""

# Packer AMI IDs — update after each packer build
web_ami_id = "ami-0fa4a29703d31133d"
app_ami_id = "ami-0ef9289afe68cd4b0"
