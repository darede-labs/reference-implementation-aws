################################################################################
# Kubernetes Providers Configuration
################################################################################
# Helm and kubectl providers are configured here to use the EKS cluster
# These providers are used to install Karpenter and apply manifests
#
# NOTE: These providers use dynamic values from module.eks outputs
# They are configured after the cluster is created
################################################################################

# Data source to get EKS cluster info for provider configuration
# These are used by Helm and kubectl providers to connect to the cluster
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Configure Helm provider to use EKS cluster
# This allows Terraform to install Helm charts directly
# Reference: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
# Using exec with aws eks get-token to avoid dependency issues
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        data.aws_eks_cluster.this.name,
        "--region",
        local.region
      ]
    }
  }
}

# Configure kubectl provider to use EKS cluster
# This allows Terraform to apply Kubernetes manifests directly
# Using exec with aws eks get-token to avoid dependency issues
provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.this.name,
      "--region",
      local.region
    ]
  }
}
