terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key            = "platform/terraform/stacks/ec2/${{ values.name }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
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

locals {
  ami_filters = {
    "amazon-linux-2023" = { owners = ["amazon"], pattern = "al2023-ami-*-x86_64" }
    "amazon-linux-2"    = { owners = ["amazon"], pattern = "amzn2-ami-hvm-*-x86_64-gp2" }
    "ubuntu-22.04"      = { owners = ["099720109477"], pattern = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" }
  }
  selected_ami = local.ami_filters["${{ values.amiType }}"]
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = local.selected_ami.owners
  filter {
    name   = "name"
    values = [local.selected_ami.pattern]
  }
}

# Get subnet info to extract VPC ID
data "aws_subnet" "selected" {
  id = "${{ values.subnetId }}"
}

{%- if values.securityGroupIds | length == 0 %}
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${{ values.name }}-sg"
  description = "Security group for EC2 instance ${{ values.name }}"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress_cidr_blocks = ["10.0.0.0/8"]
  ingress_rules       = ["ssh-tcp"]
  egress_rules        = ["all-all"]
}
{%- endif %}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name          = "${{ values.name }}"
  ami           = data.aws_ami.selected.id
  instance_type = "${{ values.instanceType }}"
  monitoring    = true

  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = {% if values.securityGroupIds | length > 0 %}${{ values.securityGroupIds | dump }}{% else %}[module.security_group.security_group_id]{% endif %}
  associate_public_ip_address = ${{ values.associatePublicIp }}
  {%- if values.keyPairName %}
  key_name                    = "${{ values.keyPairName }}"
  {%- endif %}
  {%- if values.userdata %}
  user_data                   = <<-EOF
${{ values.userdata }}
EOF
  {%- endif %}

  root_block_device = [{
    volume_size = ${{ values.rootVolumeSize | default(30) }}
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

output "public_ip" {
  value = module.ec2_instance.public_ip
}

output "security_group_id" {
  value = {% if values.securityGroupIds | length > 0 %}"${{ values.securityGroupIds[0] }}"{% else %}module.security_group.security_group_id{% endif %}
}
