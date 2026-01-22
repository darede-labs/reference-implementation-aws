# ⚠️ DEPRECATED: Variables are now loaded from ../../config.yaml via locals.tf
#
# This file is kept for backward compatibility only.
# All configuration should be done in config.yaml at the repository root.
#
# See config.yaml for:
#   - cluster_name
#   - region
#   - auto_mode
#   - node_groups (instance types, scaling, capacity type)
#   - vpc (create/existing, CIDR, AZs, NAT gateway)
#   - domains and subdomains
#   - tags

# No variables needed - everything comes from config.yaml

# Sensitive overrides (avoid hardcoding secrets in config.yaml)
variable "backstage_postgres_password" {
  description = "Backstage RDS password (sensitive). Prefer TF_VAR_backstage_postgres_password."
  type        = string
  sensitive   = true
  default     = null
}

variable "github_token" {
  description = "GitHub token used by Backstage integrations."
  type        = string
  sensitive   = true
  default     = null
}

variable "backstage_oidc_client_secret" {
  description = "Backstage OIDC client secret (optional override)."
  type        = string
  sensitive   = true
  default     = null
}

variable "argocd_admin_password" {
  description = "ArgoCD admin password for Backstage integration (optional override)."
  type        = string
  sensitive   = true
  default     = null
}
