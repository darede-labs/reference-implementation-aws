terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "idp-poc-terraform-state-948881762705"
    key            = "platform/terraform/stacks/ec2/${{ values.name }}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "idp-poc-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = "${{ values.environment }}"
      ManagedBy   = "Terraform"
      CreatedVia  = "Backstage"
      Owner       = "${{ values.owner }}"
    }
  }
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name          = "${{ values.name }}"
  ami           = data.aws_ami.selected.id
  instance_type = "${{ values.instanceType }}"
  monitoring    = true

  root_block_device = [{
    volume_size = ${{ values.rootVolumeSize }}
    volume_type = "gp3"
    encrypted   = true
  }]

  tags = {
    Name        = "${{ values.name }}"
    Environment = "${{ values.environment }}"
  }
}

output "instance_id" {
  value = module.ec2_instance.id
}

output "private_ip" {
  value = module.ec2_instance.private_ip
}
