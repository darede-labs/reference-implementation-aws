.PHONY: help init-vpc init-eks plan-vpc plan-eks apply-vpc apply-eks destroy-eks destroy-vpc configure-kubectl validate

AWS_PROFILE := darede
AWS_REGION := us-east-1

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

##@ Infrastructure

init-vpc: ## Initialize VPC Terraform
	cd terraform/vpc && terraform init -backend-config="profile=$(AWS_PROFILE)"

init-eks: ## Initialize EKS Terraform
	cd terraform/eks && terraform init -backend-config="profile=$(AWS_PROFILE)"

plan-vpc: init-vpc ## Plan VPC changes
	cd terraform/vpc && terraform plan

plan-eks: init-eks ## Plan EKS changes
	cd terraform/eks && terraform plan

apply-vpc: init-vpc ## Apply VPC infrastructure
	cd terraform/vpc && terraform apply -auto-approve

apply-eks: init-eks ## Apply EKS infrastructure
	cd terraform/eks && terraform apply -auto-approve

destroy-eks: init-eks ## Destroy EKS cluster
	cd terraform/eks && terraform destroy -auto-approve

destroy-vpc: init-vpc ## Destroy VPC
	cd terraform/vpc && terraform destroy -auto-approve

##@ Kubernetes

configure-kubectl: ## Configure kubectl for EKS cluster
	aws eks update-kubeconfig --region $(AWS_REGION) --name platform-eks --profile $(AWS_PROFILE)

validate: configure-kubectl ## Validate cluster is ready
	@echo "=== Checking nodes ==="
	kubectl get nodes
	@echo "\n=== Checking pods ==="
	kubectl get pods -A
	@echo "\n=== Checking Karpenter ==="
	kubectl get pods -n karpenter
	kubectl get nodepool
	kubectl get ec2nodeclass
	@echo "\n=== Checking cluster info ==="
	kubectl cluster-info

test-karpenter: configure-kubectl ## Test Karpenter node provisioning
	@echo "Creating test deployment to trigger Karpenter..."
	kubectl create deployment karpenter-test --image=public.ecr.aws/eks-distro/kubernetes/pause --replicas=3 || true
	@echo "Waiting for nodes..."
	@sleep 30
	kubectl get nodes -l karpenter.sh/managed=true
	kubectl get pods -l app=karpenter-test
	@echo "\nCleanup test deployment? Run: kubectl delete deployment karpenter-test"

##@ Complete workflows

install: apply-vpc apply-eks configure-kubectl validate ## Install everything (VPC + EKS)
	@echo "\n✅ Platform infrastructure deployed successfully"
	@echo "Next step: Install Karpenter (coming in Phase C)"

destroy: destroy-eks destroy-vpc ## Destroy everything (EKS first, then VPC)
	@echo "\n✅ All infrastructure destroyed"
