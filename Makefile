.PHONY: install validate-config terraform bootstrap verify clean doctor preflight preflight-dry-run

# Main installation target - ArgoCD does the rest!
install: validate-config terraform bootstrap verify
	@echo "✅ Installation complete!"

# Pre-flight check (with warnings about existing resources)
preflight: doctor
	@echo "🔍 Running pre-flight check..."
	@./scripts/pre-flight-check.sh

# Pre-flight check in dry-run mode (no warnings about existing resources)
preflight-dry-run: doctor
	@echo "🔍 Running pre-flight check (dry-run)..."
	@./scripts/pre-flight-check.sh --dry-run

# Validate config.yaml (non-sensitive) + secrets (ENV/SSM)
validate-config:
	@echo "🔍 Validating configuration..."
	@./scripts/validate-config.sh || (echo "💡 Tip: Run 'make doctor' to check CLI tools"; exit 1)

# Terraform infrastructure (idempotent)
terraform:
	@echo "🏗️  Provisioning infrastructure..."
	@./scripts/install-infra.sh

# Bootstrap ONLY ArgoCD + apply applications
bootstrap:
	@echo "🚀 Bootstrapping ArgoCD + Applications..."
	@./scripts/bootstrap-kubernetes.sh
	@echo ""
	@echo "⏳ Waiting for applications to sync..."
	@./scripts/wait-for-sync.sh 300 || echo "⚠️  Some applications are still syncing (this is normal)"

# Verify installation health (comprehensive check)
verify:
	@echo "🔍 Verifying installation..."
	@./scripts/verify-installation.sh

# Clean up resources
clean:
	@echo "🧹 Cleaning up..."
	@./scripts/destroy-cluster.sh

# Check required CLI tools are installed
doctor:
	@echo "🔍 Checking required CLI tools..."
	@MISSING=$$(for tool in aws kubectl helm yq jq gomplate terraform; do \
		command -v $$tool >/dev/null 2>&1 || echo $$tool; \
	done); \
	if [ -n "$$MISSING" ]; then \
		echo "❌ Missing tools: $$MISSING"; \
		echo ""; \
		echo "Install missing tools:"; \
		echo "  - aws: https://aws.amazon.com/cli/"; \
		echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"; \
		echo "  - helm: https://helm.sh/docs/intro/install/"; \
		echo "  - yq: https://github.com/mikefarah/yq"; \
		echo "  - jq: https://stedolan.github.io/jq/download/"; \
		echo "  - gomplate: https://docs.gomplate.ca/installing/"; \
		echo "  - terraform: https://www.terraform.io/downloads"; \
		exit 1; \
	else \
		echo "✅ All required tools installed"; \
	fi
