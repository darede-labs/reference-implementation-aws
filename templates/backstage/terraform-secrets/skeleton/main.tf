terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "idp-poc-terraform-state-948881762705"
    key            = "platform/terraform/stacks/secrets/${{ values.name }}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "idp-poc-terraform-locks"
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

resource "aws_secretsmanager_secret" "this" {
  name        = "${{ values.name }}"
  description = "${{ values.description }}"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({ "placeholder" = "update-me" })
  lifecycle { ignore_changes = [secret_string] }
}

output "secret_arn" { value = aws_secretsmanager_secret.this.arn }
output "secret_name" { value = aws_secretsmanager_secret.this.name }
