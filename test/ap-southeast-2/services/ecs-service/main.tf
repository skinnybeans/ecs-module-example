provider "aws" {
  profile = ""
  region  = var.region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/some.repo"
    }
  }
}

# Variables passed down through Terragrunt .hcl files
variable "region" {
  type        = string
  description = "Region to deploy resources"
  default     = ""
}

variable "environment" {
  type        = string
  description = "environment resources are deployed to"
  default     = ""
}

# Grab VPC and subnet details from parameter store
# These need to be written out by the VPC creation module
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.environment}/vpc/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.environment}/vpc/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${var.environment}/vpc/public_subnet_ids"
}

# Grab the wild card cert we want
# Clickopsing the cert is easiest
data "aws_acm_certificate" "example" {
  domain   = "*.${local.domain}"
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "example" {
  name = local.domain
}

locals {
  ## common locals

  # need to sort out how domains/certs will be managed in terraform
  # likely not in the same place as the cluster and tasks
  domain = "sorcererdecks.com"

  ## web specific
  web_ecr_repos_name = "example-web"

  ## worker specific
  worker_ecr_repos_name = "example-worker"

  ## container image tag
  container_image_tag = "latest"
}

##
## Cluster to run tasks on
##
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-service-cluster"

  tags = {
    Name = "${var.environment}-service-cluster"
  }
}

##
##  example web task with load balancer
##
module "example_web_ecs" {
  # source = "../../../../modules/ecs_fargate_web"
  source = "git::https://github.com/skinnybeans/tfmod-ecs-fargate-web?ref=v1.0.0"

  ##  AWS general variables
  gen_region      = var.region
  gen_environment = var.environment

  ##  Networking
  net_vpc_id                   = data.aws_ssm_parameter.vpc_id.value
  net_load_balancer_subnet_ids = jsondecode(data.aws_ssm_parameter.public_subnet_ids.value)
  net_task_subnet_ids          = jsondecode(data.aws_ssm_parameter.public_subnet_ids.value)

  ##  ECS cluster
  cluster_name = aws_ecs_cluster.main.name
  cluster_id   = aws_ecs_cluster.main.id

  ##  Task
  task_name   = "example-web"
  task_cpu    = 2048
  task_memory = 8192
  task_container_environment = [
    {
      name  = "ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "NEW_RELIC_APP_NAME"
      value = "web-test.example.com"
    }
  ]

  # This is how to pull it from an ECR repo
  # task_container_image     = "${data.identity.account_id}.dkr.ecr.${var.region}.amazonaws.com/${local.web_ecr_repos_name}"
  # task_container_image_tag = local.container_image_tag

  # For this example, just pull something from docker hub
  task_container_image     = "httpd"
  task_container_image_tag = local.container_image_tag
  task_container_port      = 80

  ##  Service
  ## Add any other security groups required IE for accessing database
  # service_addition_sg_ids = [data.aws_ssm_parameter.sg_write_id.value]

  ##  Load balancer
  # TODO: expose session stickness as config
  lb_idle_timeout    = 120
  lb_certificate_arn = data.aws_acm_certificate.example.arn

  ## Scaling
  scaling_min_capacity = 2
  scaling_max_capacity = 4

  ## Health check
  health_interval = 60
  health_timeout  = 30
  health_path     = "/"
  health_matcher  = "200-499"
}

##
##  DNS for example-test
##
resource "aws_route53_record" "example_test" {
  zone_id = data.aws_route53_zone.example.id
  name    = "test-${var.region}"
  type    = "A"
  alias {
    name                   = module.example_web_ecs.lb_dns_name
    zone_id                = module.example_web_ecs.lb_dns_zone_id
    evaluate_target_health = true
  }
}

##
##  worker example
##
module "worker_example_ecs" {
  source = "git::https://github.com/skinnybeans/tfmod-ecs-fargate-worker?ref=v1.0.0"

  ##  AWS general variables
  gen_region      = var.region
  gen_environment = var.environment

  ##  Networking
  net_vpc_id          = data.aws_ssm_parameter.vpc_id.value
  net_task_subnet_ids = jsondecode(data.aws_ssm_parameter.public_subnet_ids.value)

  ##  ECS cluster
  cluster_name = aws_ecs_cluster.main.name
  cluster_id   = aws_ecs_cluster.main.id

  ##  Task
  task_name   = "example-worker"
  task_cpu    = 256
  task_memory = 512
  task_container_environment = [
    {
      name  = "ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "NEW_RELIC_APP_NAME"
      value = "worker-test.example.com"
    }
  ]

  #task_container_image     = "${data.identity.account_id}.dkr.ecr.${var.region}.amazonaws.com/${local.worker_ecr_repos_name}"
  #task_container_image_tag = local.container_image_tag

  # For this example, just pull something from docker hub
  task_container_image     = "httpd"
  task_container_image_tag = local.container_image_tag
  task_container_port      = 80

  ##  Service
  #service_addition_sg_ids = [data.aws_ssm_parameter.sg_write_id.value]

  ## Scaling
  scaling_min_capacity = 1
  scaling_max_capacity = 1
}
