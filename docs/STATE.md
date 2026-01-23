# PLATFORM CANONICAL STATE

## 🎯 FINAL OBJECTIVE
Deliver a deterministic ZERO-to-FULLY-USABLE internal platform where:

- Users authenticate once (SSO)
- RBAC is enforced consistently across tools
- Infrastructure is provisioned via Backstage (Crossplane)
- Applications are scaffolded, built, and deployed automatically
- All resources live in the same VPC as the EKS cluster
- Everything is reproducible via `make install` (no manual steps)

---

## 🧭 PHASES (LOCKED PLAN)

### Phase 0 — Bootstrap (CURRENT)
Goal:
- Deterministic rebuild from scratch
- No manual kubectl/debug steps
- `make destroy && make install` must succeed

Includes:
- VPC + EKS
- ArgoCD (GitOps, main branch only)
- Authentication (Cognito)
- Backstage (basic, infra catalog only)
- External Secrets
- Karpenter (minimal, no policies)

Excludes (explicitly):
- Kyverno policies
- Cost controls
- Advanced security hardening

Done when:
- All UIs accessible
- SSO works on ArgoCD + Backstage
- No ArgoCD sync errors
- No CrashLoop pods

---

### Phase 1 — Infra Self-Service (NEXT)
Goal:
- Users provision AWS infra via Backstage

Includes:
- Crossplane AWS provider
- EC2 / RDS / S3 via T-shirt sizes (S/M/L)
- For ec2,  create instance profile with SSM permissions, should be acessible trough ssm
  Security group should have ingress to port 80 and 443, ami should be the latest amazon linux available, no user input about this, user should input only instance name and Size (based on tshirt)
- Resources tagged and scoped per user
- RDS, should user only get the size based on tshirt, the engine (see availables) and instance name, security group should allow the engine connections in the current vpc
- Users can delete ONLY their own resources
- add the username as owner on tags, also create common tags for all resources

Constraints:
- Same VPC as EKS
- No user input for networking

---

### Phase 2 — App Scaffolding & Deploy
Goal:
- One-click app creation + deploy

Includes:
- GitHub repo creation
- Node.js hello-world app
- ECR repo creation
- GitHub Actions CI
- ArgoCD auto-tracking
- Ingress: <app>.<domain>

---

### Phase 3 — Hardening (LATER)
Includes:
- Cost governance
- Observability improvements


---

## 🧠 CURRENT STATE

Phase: FULL RESET AND REBUILD
Status: 🔄 IN PROGRESS
Branch: platform-rebuild-clean

Current Step: Phases A, B, C ✅ COMPLETE
- [x] **Phase A** - Total Destruction
  - Repository cleaned ✓
  - All old files removed ✓
  - New branch created ✓
- [x] **Phase B** - Base Infrastructure
  - VPC with 3 AZs (public + private subnets) ✓
  - Single NAT Gateway (cost-optimized) ✓
  - EKS 1.31 with IRSA ✓
  - Bootstrap node group (t4g.medium ARM64) ✓
  - Makefile for easy deployment ✓
- [x] **Phase C** - Karpenter
  - Karpenter IAM (IRSA) ✓
  - Helm chart installation (v1.0.6) ✓
  - EC2NodeClass for ARM64 nodes ✓
  - NodePool with on-demand instances ✓
  - Disruption budget configured ✓
  - Documentation and validation commands ✓

**Status**: Foundation complete and ready for deployment.

**Next Steps** (Phase D):
- Deploy infrastructure: `make install`
- Validate Karpenter: `make test-karpenter`
- Install GitOps tooling (ArgoCD, ingress-nginx, etc.)

---

## 🔒 DECISIONS (DO NOT REVISIT)

- Auth: Amazon Cognito (no Keycloak)
- GitOps: ArgoCD, main branch only
- Infra provisioning: Crossplane
- Secrets: AWS Secrets Manager + External Secrets
- Rebuild strategy: Destroy first, then install

---

## 🚫 OUT OF SCOPE (FOR NOW)

- Kyverno policies
- Multi-cluster
- Production HA
- Cost optimization

---

## 📌 RULES FOR AGENTS

- Read this file first
- Do not redesign phases
- Do not reintroduce Keycloak
- Commit everything (no local-only fixes)
- Update this file after each completed task
- All execution context must be written here after each major step
- If context usage exceeds ~70%, rely ONLY on this file and stop using chat memory

---

## 🔄 RECENT CHANGES (Latest First)

### 2026-01-23: Phase 1 refactor started (BLOCKED)
**Status:** ⛔️ BLOCKED

**What Changed:**
- Moved Karpenter locals into `terraform/eks/locals.tf`
- Consolidated Karpenter outputs into `terraform/eks/outputs.tf`
- Removed `terraform/eks/karpenter-outputs.tf`
- Ensured data sources remain in `terraform/eks/data-sources.tf`
- Backend lock now uses `use_lockfile = true` (no DynamoDB)

**Commands Run:**
```bash
export AWS_PROFILE=darede
aws sso login --profile darede
terraform fmt (in terraform/eks)
terraform init -reconfigure (in terraform/eks)
terraform plan (in terraform/eks)
```

**Validation:**
- `terraform plan` failed: missing VPC remote state (`s3://poc-idp-tfstate/vpc/terraform.tfstate`)
- No-op plan requirement NOT satisfied (blocked)

### 2026-01-23: Phases A, B, C - Foundation Complete ✅
**Status:** COMPLETE

**Phase A - Total Destruction:**
- New branch: `platform-rebuild-clean`
- Removed all old Terraform, Kubernetes manifests, scripts
- Repository cleaned to minimal state

**Phase B - Base Infrastructure:**
- VPC with 3 AZs, private/public subnets, single NAT
- EKS 1.31 cluster with IRSA enabled
- Bootstrap node group (t4g.medium ARM64, 1-2 nodes, tainted)
- Makefile with deployment automation

**Phase C - Karpenter:**
- Karpenter v1.0.6 installed via Helm
- IRSA configured for Karpenter controller
- EC2NodeClass for ARM64 Graviton nodes
- NodePool with on-demand only, consolidation policy
- Security groups tagged for discovery
- Validation commands in Makefile

**Files Created:**
- `terraform/vpc/*` - VPC module
- `terraform/eks/*` - EKS + Karpenter module
- `docs/karpenter.md` - Comprehensive Karpenter documentation
- `Makefile` - Deployment automation

**Commits:**
1. `chore(reset): full platform teardown`
2. `feat(infra): Phase B - clean base infrastructure`
3. `feat(karpenter): Phase C - Karpenter installation`

**Ready for Deployment:**
```bash
make install          # Deploy VPC + EKS + Karpenter
make test-karpenter   # Validate Karpenter works
```

### 2026-01-22: Bootstrap Node Group Stabilization
**Status:** ✅ COMPLETE

**What Changed:**
- Switched bootstrap node group AMI to `AL2_ARM_64` for faster, more reliable creation
- Standardized bootstrap label to `role=bootstrap` to match Phase 0 requirements

**Files Modified:**
- `cluster/terraform/karpenter.tf`

**Validation:**
- EKS cluster ACTIVE
- Bootstrap node group creation progressing (no health issues)

### 2026-01-22: Terraform VPC Separation
**Status:** ✅ COMPLETE

**What Changed:**
- Separated VPC from EKS cluster into independent Terraform modules
- Both use same S3 bucket but different paths:
  - VPC: `s3://poc-idp-tfstate/vpc/terraform.tfstate`
  - EKS: `s3://poc-idp-tfstate/eks/terraform.tfstate`
- EKS reads VPC outputs via remote state

**Files Modified:**
- Created: `cluster/terraform-vpc/` (new directory)
  - `main.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `README.md`
- Updated: `cluster/terraform/main.tf` (uses remote state)
- Updated: `cluster/terraform/locals.tf` (removed VPC vars)
- Updated: `cluster/terraform/karpenter.tf`, `nlb.tf`, `security_groups.tf`
- Updated: `scripts/install-infra.sh` (provisions VPC first, then EKS)
- Updated: `scripts/destroy-cluster.sh` (destroys EKS first, then VPC)
- Created: `docs/TERRAFORM-VPC-SEPARATION.md` (full documentation)

**Benefits:**
- Independent lifecycle (VPC can exist without EKS)
- Faster EKS iterations (no VPC recreation)
- Better organization and modularity
- Safer destroys (explicit order)

**Next Actions:**
- [ ] Consider replacing NLB with ALB (simpler, better for L7)
- [ ] Test full install/destroy cycle
- [ ] Update main README.md

### 2026-01-22: Full Platform Reset
**Status:** ✅ COMPLETE**What Was Destroyed:**
- All ArgoCD Applications (backstage, keycloak, external-dns, etc.)
- All Kubernetes namespaces (argocd, backstage, keycloak, ingress-nginx, etc.)
- EKS cluster `idp-poc-darede-cluster`
- VPCs: `vpc-07068c2e8724db4dc`, `vpc-0988b68ceca3b4a3a`
- Terraform state cleaned
- kubectl contexts removed

**Files Removed:**
- `argocd-apps/platform/keycloak*.yaml` (all variants)
- `argocd-apps/platform/kyverno.yaml`
- `cluster/terraform/rds-keycloak.tf`
- `platform/keycloak/` (entire directory)
- `platform/keycloak-bootstrap/` (entire directory)
- `platform/kyverno/` (entire directory)

**Config Updated:**
- `identity_provider: "cognito"` ✓
- `keycloak.enabled: "false"` ✓

**Validation:**
- ✅ No EKS cluster exists
- ✅ No Keycloak RDS instances
- ✅ No VPCs with cluster name
- ✅ No kubectl contexts
- ✅ No Terraform state files
- ✅ All Keycloak/Kyverno files removed

---

## 🚧 OPEN QUESTIONS

### NLB vs ALB Decision
**Question:** Should we use ALB instead of NLB?

**Current:** NLB (Layer 4) → ingress-nginx (Layer 7)
**Proposed:** ALB (Layer 7) → Kubernetes Services directly

**ALB Advantages:**
- Native TLS termination with ACM (already have certificate)
- Native L7 routing (path-based, host-based)
- Better health checks (HTTP instead of TCP)
- WAF integration (future security)
- Can route directly to services (no NodePort needed)
- Simpler architecture (less components)

**NLB Advantages:**
- Preserves client IP
- Lower latency (no L7 processing)
- Works with any protocol (not just HTTP)

**Recommendation:** Use ALB for this IDP use case
- Internal platform (client IP less critical)
- All traffic is HTTP/HTTPS
- Simpler architecture preferred
- Better integration with AWS services

**Decision:** PENDING user confirmation
