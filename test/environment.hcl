# inputs are referenced from the Terraform files
inputs = {
  environment = "test"
}

## locals are referenced from the terragrunt config
locals {
  remote_state_region = "us-west-1"
  environment = "test"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = "some-terraform-vpc-${local.environment}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.remote_state_region
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}