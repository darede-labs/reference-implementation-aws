terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key          = "platform/terraform/stacks/security-group/${{ values.name }}/terraform.tfstate"
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

resource "aws_security_group" "this" {
  name        = "${{ values.name }}"
  description = "${{ values.description | default('Managed by Terraform via Backstage') }}"
  vpc_id      = "${{ values.vpcId }}"

  {%- for rule in values.ingressRules %}
  ingress {
    from_port   = ${{ rule.fromPort }}
    to_port     = ${{ rule.toPort }}
    protocol    = "${{ rule.protocol }}"
    cidr_blocks = ["${{ rule.cidrBlocks }}"]
    description = "${{ rule.description }}"
  }
  {%- endfor %}

  {%- if values.egressRules and values.egressRules | length > 0 %}
  {%- for rule in values.egressRules %}
  egress {
    from_port   = ${{ rule.fromPort }}
    to_port     = ${{ rule.toPort }}
    protocol    = "${{ rule.protocol }}"
    cidr_blocks = ["${{ rule.cidrBlocks }}"]
    description = "${{ rule.description }}"
  }
  {%- endfor %}
  {%- else %}
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  {%- endif %}

  tags = {
    Name = "${{ values.name }}"
  }
}

output "security_group_id" { value = aws_security_group.this.id }
output "security_group_arn" { value = aws_security_group.this.arn }
