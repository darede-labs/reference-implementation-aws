# Platform Features and Capabilities

## Overview

Backstage IDP provides self-service infrastructure provisioning via Terraform templates.

## Available Templates

### Infrastructure Templates

| Template | Purpose | Resources Created |
|----------|---------|-------------------|
| **terraform-s3** | Secure S3 buckets | Bucket, encryption, versioning, lifecycle |
| **terraform-ec2-ssm** | EC2 with SSM access | Instance, security group, IAM role |
| **terraform-vpc** | Network isolation | VPC, subnets, NAT, IGW, routes |
| **terraform-rds** | Managed databases | RDS instance, subnet group, backups |
| **terraform-alb** | Load balancing | ALB, listeners, target groups |
| **terraform-cloudfront-s3** | CDN delivery | CloudFront, S3, OAI, SSL |
| **terraform-lambda** | Serverless compute | Lambda, IAM role, API Gateway |
| **terraform-dynamodb** | NoSQL database | Table, indexes, encryption |
| **resource-manager** | Resource management | View/delete resources |
| **terraform-destroy** | Cleanup | Destroy infrastructure |
| **terraform-unlock** | State management | Unlock stuck state |

## Architecture

**Provisioning Flow:**
```
User → Backstage Form → GitHub Repo → Argo Workflow → Terraform → AWS → Catalog Update
```

**Components:**
- **Backstage:** UI and orchestration
- **GitHub:** Code repository (darede-labs org)
- **Argo Workflows:** Terraform execution engine
- **AWS:** Infrastructure provider
- **S3:** Terraform state storage (poc-idp-tfstate)

## Security

**Access Control:**
- ✅ Authentication required (Cognito OIDC)
- ✅ User-scoped resource listing
- ✅ API authorization via X-Backstage-User header
- ✅ Cross-user enumeration blocked

**Resource Protection:**
- ✅ All resources tagged (ManagedBy: backstage, Owner: user)
- ✅ IAM least privilege per service account
- ✅ Terraform state encrypted at rest
- ✅ Input validation and sanitization

**Audit Trail:**
- GitHub commits (who/what/when)
- Argo Workflow logs (execution history)
- Terraform state (infrastructure state)
- CloudWatch Logs (runtime logs)

## Resource Lifecycle

**Create:** Template → Form → Repo → Workflow → AWS
**Monitor:** Resource Manager UI or API endpoint
**Delete:** Resource Manager → Destroy workflow → Cleanup

## Best Practices

**For Users:**
1. Use lowercase kebab-case naming
2. Include environment suffix (-dev, -prod)
3. Add tags: Environment, Owner, CostCenter
4. Delete unused resources monthly

**For Operators:**
1. Keep Terraform providers updated
2. Test templates in staging first
3. Monitor state lock duration
4. Review costs via AWS tags

## Troubleshooting

**Workflow Failed:** Check `kubectl logs -n argo-workflows <pod>`
**Resources Not Listed:** Verify state file in S3
**State Locked:** Use terraform-unlock template

## Metrics

- Active users per day
- Templates executed per week
- Resources provisioned per month
- Average provisioning time
