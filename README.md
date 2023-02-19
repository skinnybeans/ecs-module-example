# Terraform ECS example

This repo aims to show a scaffolding for:

- Using Terragrunt
- Laying out a Terraform repo for multi environment, multi account structure
- Simple use of the 3 musketeers pattern
- Deploying a simple VPC in two regions
- Deploying a simple ECS cluster in two regions

## How it works

Config is nested at various levels of the directory tree in `terragrunt.hcl` files.

The values that are set in these files are then used in the terraform modules.
This enables the removal of all environment and region specific hardcoding in the modules themselves.

The setup creates:

- One state bucket per environment (deploying resources in different regions will result in cross region communication for state)

### Environment

File: `environment.hcl`

- Contains a template for backend config.
  - This allows different environments to store their state file in different buckets
  - The state key matches the directory path
  - There is only one state file per environment, so cross region access will occur
    - If this is undesirable, the back end config could be moved to the `region.hcl` file

Terragrunt generates a `backend.tf` file for each subdirectory before running any terraform commands.

Also sets a local for the environment name that can then be referenced later to help namespace things well.

### Region

File: `region.hcl`

Sets a local, this time for region. This is used to do provider setup.

If you have region agnostic resources, they can live a level up the tree and not in a region specific directory.

This also helps make it clear which resources are shared amongst regions.

### Module

File: `terragrunt.hcl`

Unfortunately there's no easy way to chain inherit config yet using terragrunt.
This means each child module must inherit the three files above separately like so:

```hcl
include "region" {
  path = find_in_parent_folders("region.hcl")
}

include "environment" {
  path = find_in_parent_folders("environment.hcl")
}
```

## Local Setup

### Using 3 musketeers pattern

You will need:

- docker
- docker-compose
- make (only an issue on windows really...)

### Using tools directly

You will need:

- terraform
  - installed in a way you can updated it regularly and easily (such as homebrew if using MacOS)
- terragrunt
  - if you want to process multiple directories at once
  - again make sure you update your install regularly

## Local Running

When dealing with this repo locally the assumption is made you will be working on only one directory at a time.

If you are modifying child modules it may be helpful to run plan over the whole repo so you understand the blast radius of your changes!!

### Make targets

#### Single directory

To work with a single directory at a time.
Doing a plan/apply over everything can be time consuming! Leave that to the pipeline.

Initialise terraform:

```bash
make init-dir dir=path/to/your/terraform
```

Plan terraform:

```bash
make plan-dir dir=path/to/your/terraform
```

Apply terraform:

```bash
make apply-dir dir=path/to/your/terraform
```

#### The whole thing

If you want to do a plan over all the Terraform:

```bash
make plan
```

```bash
make apply
```

There are a few other make targets in the `Makefile`, browse at your leisure

### Using Terraform directly

Due to the passing of config, you need to use Terragrunt rather than Terraform.

The command are similar, eg `terraform plan` = `terragrunt plan`

## The pipeline

Runs on buildkite, check the `.buildkite/pipeline.yaml` file for the details.

### A note on version pinning

No version pinning is used in the pipeline, so we are always testing against the lastest versions of:

- Terraform
- Terragrunt
- Terraform AWS provider

The pipeline runs a `test` environment apply first, to try and detect any potential problems before running the other environments.

A tradeoff has been made between breaking things (and fixing) early and accruing technical debt (by being far behind on versions).
