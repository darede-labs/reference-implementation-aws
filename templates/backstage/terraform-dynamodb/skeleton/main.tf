terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

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
      OwnerEmail  = "${{ values.ownerEmail }}"
    }
  }
}

module "dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 4.0"

  name      = "${{ values.name }}"
  hash_key  = "${{ values.partitionKey.name }}"
  {%- if values.sortKey and values.sortKey.name %}
  range_key = "${{ values.sortKey.name }}"
  {%- endif %}

  billing_mode   = "${{ values.billingMode | default('PAY_PER_REQUEST') }}"
  {%- if values.billingMode == 'PROVISIONED' %}
  read_capacity  = ${{ values.readCapacity | default(5) }}
  write_capacity = ${{ values.writeCapacity | default(5) }}
  {%- endif %}

  # Attributes
  attributes = [
    {
      name = "${{ values.partitionKey.name }}"
      type = "${{ values.partitionKey.type }}"
    }
    {%- if values.sortKey and values.sortKey.name %},
    {
      name = "${{ values.sortKey.name }}"
      type = "${{ values.sortKey.type }}"
    }
    {%- endif %}
    {%- for gsi in values.globalSecondaryIndexes %},
    {
      name = "${{ gsi.partitionKey }}"
      type = "${{ gsi.partitionKeyType | default('S') }}"
    }
    {%- if gsi.sortKey %},
    {
      name = "${{ gsi.sortKey }}"
      type = "${{ gsi.sortKeyType | default('S') }}"
    }
    {%- endif %}
    {%- endfor %}
  ]

  # Point-in-Time Recovery
  point_in_time_recovery_enabled = ${{ values.enablePointInTimeRecovery | default(true) }}

  # Server-Side Encryption
  server_side_encryption_enabled = ${{ values.enableEncryption | default(true) }}

  # TTL
  {%- if values.enableTTL %}
  ttl_enabled        = true
  ttl_attribute_name = "${{ values.ttlAttribute | default('ttl') }}"
  {%- endif %}

  # Streams
  {%- if values.streamEnabled %}
  stream_enabled   = true
  stream_view_type = "${{ values.streamViewType | default('NEW_AND_OLD_IMAGES') }}"
  {%- endif %}

  # Global Secondary Indexes
  {%- if values.globalSecondaryIndexes and values.globalSecondaryIndexes | length > 0 %}
  global_secondary_indexes = [
    {%- for gsi in values.globalSecondaryIndexes %}
    {
      name               = "${{ gsi.name }}"
      hash_key           = "${{ gsi.partitionKey }}"
      {%- if gsi.sortKey %}
      range_key          = "${{ gsi.sortKey }}"
      {%- endif %}
      projection_type    = "${{ gsi.projectionType | default('ALL') }}"
      {%- if values.billingMode == 'PROVISIONED' %}
      read_capacity      = ${{ values.readCapacity | default(5) }}
      write_capacity     = ${{ values.writeCapacity | default(5) }}
      {%- endif %}
    }{% if not loop.last %},{% endif %}
    {%- endfor %}
  ]
  {%- endif %}

  tags = {
    Name        = "${{ values.name }}"
    Environment = "${{ values.environment }}"
    Owner       = "${{ values.owner }}"
    {%- for tag in values.tags %}
    "${{ tag.key }}" = "${{ tag.value }}"
    {%- endfor %}
  }
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = module.dynamodb_table.dynamodb_table_id
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = module.dynamodb_table.dynamodb_table_arn
}

output "table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = module.dynamodb_table.dynamodb_table_stream_arn
}
