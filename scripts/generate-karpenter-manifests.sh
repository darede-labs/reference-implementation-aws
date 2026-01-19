#!/usr/bin/env bash
################################################################################
# Generate Karpenter Manifests from Terraform Outputs
################################################################################
# This script generates NodePool and EC2NodeClass manifests with actual values
# from Terraform outputs (cluster name, role ARN, etc.)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../cluster/terraform"
OUTPUT_DIR="${SCRIPT_DIR}/../platform/karpenter"

# Get Terraform outputs
cd "$TERRAFORM_DIR"

CLUSTER_NAME=$(terraform output -raw cluster_name)
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
CLUSTER_CA=$(terraform output -raw cluster_certificate_authority_data 2>/dev/null || echo "")
KARPENTER_NODE_ROLE=$(terraform output -raw karpenter_node_role_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw region)

# Get cloud_economics tag from Terraform
CLOUD_ECONOMICS_TAG=$(terraform output -json validation_summary 2>/dev/null | jq -r '.cloud_economics_tag // "Darede-IDP::devops"')

if [ -z "$KARPENTER_NODE_ROLE" ]; then
    echo "Warning: karpenter_node_role_name output not found, using default pattern"
    KARPENTER_NODE_ROLE="Karpenter-${CLUSTER_NAME}-${AWS_REGION}"
fi

mkdir -p "$OUTPUT_DIR"

################################################################################
# Generate EC2NodeClass
################################################################################

cat > "$OUTPUT_DIR/ec2nodeclass.yaml" <<EOF
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI Selection
  amiSelectorTerms:
    # Use latest EKS-optimized Amazon Linux 2023 AMI
    - alias: al2023@latest

  # IAM Role for nodes (created by Terraform)
  role: "${KARPENTER_NODE_ROLE}"

  # Subnet selection (private subnets for EKS)
  subnetSelectorTerms:
    - tags:
        kubernetes.io/role/internal-elb: "1"

  # Security group selection (cluster security group)
  securityGroupSelectorTerms:
    - tags:
        aws:eks:cluster-name: "${CLUSTER_NAME}"

  # Block device mappings (disk configuration)
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true
        # gp3 performance settings (cost-optimized)
        iops: 3000
        throughput: 125

  # Metadata options (IMDSv2 required for security)
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required  # Require IMDSv2

  # Detailed monitoring (disabled to save costs in POC)
  detailedMonitoring: false

  # Tags applied to EC2 instances
  tags:
    Name: "karpenter-${CLUSTER_NAME}"
    ManagedBy: karpenter
    Environment: poc
    cloud_economics: "${CLOUD_ECONOMICS_TAG}"
    karpenter.sh/discovery: "${CLUSTER_NAME}"
EOF

################################################################################
# Generate NodePool
################################################################################

cat > "$OUTPUT_DIR/nodepool.yaml" <<EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  # Template for nodes launched by this NodePool
  template:
    metadata:
      # Labels applied to all nodes
      labels:
        karpenter.sh/capacity-type: spot
        workload-type: general

    spec:
      # Node class reference (defines AWS-specific configuration)
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      # Taints for workload isolation (none for default pool)
      taints: []

      # Startup taints removed after node is ready
      startupTaints: []

      # Requirements for node selection
      requirements:
        # Capacity type: prefer spot for cost savings
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]

        # Architecture: only x86_64
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        # Operating system: only linux
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Instance category: general purpose (t-series)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t"]

        # Instance generation: 2, 3, or 3a
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]

        # Specific instance types (from config.yaml)
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3a.medium", "t3.medium", "t2.medium"]

  # Limits for this NodePool
  limits:
    cpu: "20"      # Maximum 20 vCPUs across all nodes in this pool
    memory: 80Gi   # Maximum 80GB RAM across all nodes in this pool

  # Disruption settings (consolidation, expiration, etc)
  disruption:
    # Consolidation: Replace underutilized nodes with cheaper/smaller ones
    consolidationPolicy: WhenEmptyOrUnderutilized

    # Consolidate after 30 seconds of being empty
    consolidateAfter: 30s

    # Budget for disruptions (max 10% of nodes can be disrupted at once)
    budgets:
      - nodes: "10%"

  # Weight for scheduling priority (higher = preferred)
  weight: 10
EOF

echo "✓ Generated Karpenter manifests:"
echo "  - $OUTPUT_DIR/ec2nodeclass.yaml"
echo "  - $OUTPUT_DIR/nodepool.yaml"
