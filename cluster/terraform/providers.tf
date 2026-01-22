################################################################################
# Kubernetes Providers Configuration
################################################################################
# Helm and kubectl providers are configured here to use the EKS cluster
# These providers are used to install Karpenter and apply manifests
#
# NOTE: These providers use dynamic values from module.eks outputs
# They are configured after the cluster is created
################################################################################

# Configure Helm provider to use EKS cluster
# Using module outputs directly to avoid chicken-and-egg problem
# Reference: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        local.region
      ]
    }
  }
}

# Configure kubectl provider to use EKS cluster
# Using module outputs directly to avoid chicken-and-egg problem
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      local.region
    ]
  }
}
