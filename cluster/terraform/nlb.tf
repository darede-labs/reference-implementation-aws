# Network Load Balancer for Ingress-Nginx
# Managed by Terraform to avoid orphaned resources during destroy

resource "aws_lb" "ingress_nginx" {
  count = var.enable_nlb ? 1 : 0

  name               = "${local.cluster_name}-ingress-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-ingress-nlb"
    }
  )
}

# Target Group for HTTP (port 80)
resource "aws_lb_target_group" "http" {
  count = var.enable_nlb ? 1 : 0

  name     = "${local.cluster_name}-http"
  port     = 30080
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "TCP"
  }

  tags = local.tags
}

# Target Group for HTTPS (port 443)
resource "aws_lb_target_group" "https" {
  count = var.enable_nlb ? 1 : 0

  name     = "${local.cluster_name}-https"
  port     = 30443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "TCP"
  }

  tags = local.tags
}

# Listener for HTTP (port 80)
resource "aws_lb_listener" "http" {
  count = local.enable_nlb ? 1 : 0

  load_balancer_arn = aws_lb.ingress_nginx[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http[0].arn
  }
}

# Listener for HTTPS (port 443) with ACM certificate
resource "aws_lb_listener" "https" {
  count = local.enable_nlb ? 1 : 0

  load_balancer_arn = aws_lb.ingress_nginx[0].arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https[0].arn
  }
}

# Auto-attach worker nodes to target groups
resource "aws_autoscaling_attachment" "http" {
  count = local.enable_nlb ? length(module.eks.eks_managed_node_groups) : 0

  autoscaling_group_name = module.eks.eks_managed_node_groups[keys(module.eks.eks_managed_node_groups)[count.index]].node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.http[0].arn
}

resource "aws_autoscaling_attachment" "https" {
  count = local.enable_nlb ? length(module.eks.eks_managed_node_groups) : 0

  autoscaling_group_name = module.eks.eks_managed_node_groups[keys(module.eks.eks_managed_node_groups)[count.index]].node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.https[0].arn
}
