terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key          = "platform/terraform/stacks/secrets/${{ values.name | replace('/', '-') }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
    encrypt      = true
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
  description = "${{ values.description | default('Managed by Terraform via Backstage') }}"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    {%- for item in values.secretData %}
    "${{ item.key }}" = "${{ item.value }}"{% if not loop.last %},{% endif %}
    {%- endfor %}
  })
}

output "secret_arn" { value = aws_secretsmanager_secret.this.arn }
output "secret_name" { value = aws_secretsmanager_secret.this.name }
output "secret_keys" { value = [{% for item in values.secretData %}"${{ item.key }}"{% if not loop.last %}, {% endif %}{% endfor %}] }
