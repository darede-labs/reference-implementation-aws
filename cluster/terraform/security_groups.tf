################################################################################
# Security Groups - Fully Managed by Terraform
################################################################################
# All security groups are created and managed by Terraform to prevent:
# - Orphaned resources during destroy
# - Dependency conflicts
# - Manual cleanup requirements
################################################################################

################################################################################
# Ingress-Nginx Security Group
################################################################################
# This security group is pre-created for ingress-nginx to use
# Prevents Kubernetes from creating orphaned security groups

resource "aws_security_group" "ingress_nginx" {
  count = local.enable_nlb ? 1 : 0

  name_prefix = "${local.cluster_name}-ingress-nginx-"
  description = "Security group for ingress-nginx controller (managed by Terraform)"
  vpc_id      = module.vpc.vpc_id

  tags = merge(
    local.tags,
    {
      Name                                          = "${local.cluster_name}-ingress-nginx"
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
      "kubernetes.io/role/elb"                      = "1"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow HTTP traffic
resource "aws_security_group_rule" "ingress_nginx_http" {
  count = local.enable_nlb ? 1 : 0

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress_nginx[0].id
  description       = "Allow HTTP traffic from internet"
}

# Allow HTTPS traffic
resource "aws_security_group_rule" "ingress_nginx_https" {
  count = local.enable_nlb ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress_nginx[0].id
  description       = "Allow HTTPS traffic from internet"
}

# Allow NodePort traffic (30080, 30443)
resource "aws_security_group_rule" "ingress_nginx_nodeport_http" {
  count = local.enable_nlb ? 1 : 0

  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = aws_security_group.ingress_nginx[0].id
  description       = "Allow NodePort HTTP from VPC"
}

resource "aws_security_group_rule" "ingress_nginx_nodeport_https" {
  count = local.enable_nlb ? 1 : 0

  type              = "ingress"
  from_port         = 30443
  to_port           = 30443
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = aws_security_group.ingress_nginx[0].id
  description       = "Allow NodePort HTTPS from VPC"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "ingress_nginx_egress" {
  count = local.enable_nlb ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress_nginx[0].id
  description       = "Allow all outbound traffic"
}

################################################################################
# Add security group to nodes (if using managed node groups)
################################################################################

# Attach ingress-nginx security group to managed node groups
# This allows NLB to reach the NodePort services
resource "aws_security_group_rule" "nodes_ingress_from_nlb" {
  count = local.enable_nlb && !local.karpenter_enabled && !local.auto_mode ? 1 : 0

  type                     = "ingress"
  from_port                = 30080
  to_port                  = 30443
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = aws_security_group.ingress_nginx[0].id
  description              = "Allow traffic from NLB to NodePort services"
}
