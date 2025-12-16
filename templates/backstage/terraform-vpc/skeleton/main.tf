terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key          = "platform/terraform/stacks/vpc/${{ values.name }}/terraform.tfstate"
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

locals {
  # Extract VPC base (first two octets) from CIDR
  vpc_cidr_base = regex("^(\\d+\\.\\d+)", "${{ values.cidr }}")[0]

  # Separate subnets by type
  public_subnets = [
    {%- for subnet in values.subnets %}
    {%- if subnet.type == "public" %}
    {
      name = "${{ subnet.name }}"
      cidr = "${local.vpc_cidr_base}.${{ subnet.cidrSuffix }}.0/24"
      az   = "us-east-1${{ subnet.availabilityZone }}"
    },
    {%- endif %}
    {%- endfor %}
  ]

  private_subnets = [
    {%- for subnet in values.subnets %}
    {%- if subnet.type == "private" %}
    {
      name = "${{ subnet.name }}"
      cidr = "${local.vpc_cidr_base}.${{ subnet.cidrSuffix }}.0/24"
      az   = "us-east-1${{ subnet.availabilityZone }}"
    },
    {%- endif %}
    {%- endfor %}
  ]
}

resource "aws_vpc" "this" {
  cidr_block           = "${{ values.cidr }}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${{ values.name }}"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${{ values.name }}-igw"
  }
}

{%- for subnet in values.subnets %}
{%- if subnet.type == "public" %}
resource "aws_subnet" "public_${{ subnet.name | replace('-', '_') }}" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "${local.vpc_cidr_base}.${{ subnet.cidrSuffix }}.0/24"
  availability_zone       = "us-east-1${{ subnet.availabilityZone }}"
  map_public_ip_on_launch = true

  tags = {
    Name                        = "${{ values.name }}-${{ subnet.name }}"
    "kubernetes.io/role/elb"    = "1"
    Type                        = "public"
  }
}
{%- endif %}
{%- if subnet.type == "private" %}
resource "aws_subnet" "private_${{ subnet.name | replace('-', '_') }}" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "${local.vpc_cidr_base}.${{ subnet.cidrSuffix }}.0/24"
  availability_zone = "us-east-1${{ subnet.availabilityZone }}"

  tags = {
    Name                              = "${{ values.name }}-${{ subnet.name }}"
    "kubernetes.io/role/internal-elb" = "1"
    Type                              = "private"
  }
}
{%- endif %}
{%- endfor %}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${{ values.name }}-public-rt"
  }
}

{%- for subnet in values.subnets %}
{%- if subnet.type == "public" %}
resource "aws_route_table_association" "public_${{ subnet.name | replace('-', '_') }}" {
  subnet_id      = aws_subnet.public_${{ subnet.name | replace('-', '_') }}.id
  route_table_id = aws_route_table.public.id
}
{%- endif %}
{%- endfor %}

{%- if values.enableNatGateway %}
# NAT Gateway (for private subnets)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${{ values.name }}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_${{ values.subnets | selectattr('type', 'equalto', 'public') | first | attr('name') | replace('-', '_') }}.id

  tags = {
    Name = "${{ values.name }}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${{ values.name }}-private-rt"
  }
}

{%- for subnet in values.subnets %}
{%- if subnet.type == "private" %}
resource "aws_route_table_association" "private_${{ subnet.name | replace('-', '_') }}" {
  subnet_id      = aws_subnet.private_${{ subnet.name | replace('-', '_') }}.id
  route_table_id = aws_route_table.private.id
}
{%- endif %}
{%- endfor %}
{%- endif %}

output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr" { value = aws_vpc.this.cidr_block }
output "public_subnet_ids" {
  value = [
    {%- for subnet in values.subnets %}
    {%- if subnet.type == "public" %}
    aws_subnet.public_${{ subnet.name | replace('-', '_') }}.id,
    {%- endif %}
    {%- endfor %}
  ]
}
output "private_subnet_ids" {
  value = [
    {%- for subnet in values.subnets %}
    {%- if subnet.type == "private" %}
    aws_subnet.private_${{ subnet.name | replace('-', '_') }}.id,
    {%- endif %}
    {%- endfor %}
  ]
}
