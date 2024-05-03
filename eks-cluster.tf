terraform {
  required_version = ">=1.0"
  required_providers {
    random = {
      source = "hashicorp/random"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "<= 3.56"
    }
  }
}

provider "aws" {
}

resource "random_string" "random" {
  length  = 6
  special = false
  lower   = true
}

resource "random_pet" "prefix" {}

locals {
  random_name = "${random_pet.prefix.id}-${random_string.random.result}"
}

locals {
  cluster_name = "eks-${local.random_name}"
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "${local.random_name}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets       = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source                   = "terraform-aws-modules/eks/aws"
  version                  = "17.24.0"
  cluster_name             = local.cluster_name
  cluster_version          = "1.21"
  subnets                  = module.vpc.private_subnets
  write_kubeconfig         = false
  wait_for_cluster_timeout = 600
  vpc_id                   = module.vpc.vpc_id

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  worker_groups = [
    {
      name                          = "${local.cluster_name}-worker-group"
      instance_type                 = "t2.small"
      asg_desired_capacity          = 2
      additional_security_group_ids = []
    }
  ]
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}