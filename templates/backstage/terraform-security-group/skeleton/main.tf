terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key            = "platform/terraform/stacks/security-group/${{ values.name }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Environment = "${{ values.environment }}", ManagedBy = "Terraform", CreatedVia = "Backstage", Owner = "${{ values.owner }}" }
  }
}

{%- if values.vpcId %}
data "aws_vpc" "selected" {
  id = "${{ values.vpcId }}"
}
{%- else %}
data "aws_vpc" "selected" {
  default = true
}
{%- endif %}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  name        = "${{ values.name }}"
  description = "${{ values.description | default('Managed by Terraform via Backstage') }}"
  vpc_id      = data.aws_vpc.selected.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = compact([
    "${{ values.allowSsh }}" == "true" ? "ssh-tcp" : "",
    "${{ values.allowHttp }}" == "true" ? "http-80-tcp" : "",
    "${{ values.allowHttps }}" == "true" ? "https-443-tcp" : ""
  ])
  egress_rules = ["all-all"]
}

output "security_group_id" { value = module.security_group.security_group_id }
