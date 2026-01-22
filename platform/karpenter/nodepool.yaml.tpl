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

        # Architecture: ARM64 (Graviton) and x86_64 for maximum flexibility
        # Graviton instances (ARM) are ~20% cheaper with same performance
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64", "amd64"]

        # Operating system: only linux
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Instance category: T (burstable) and M (general purpose)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "m"]

        # Instance generation: 3+ for better performance
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]

        # Specific instance types - MVP cost-optimized with Graviton (ARM) support
        # Graviton instances are prioritized for ~20% cost savings
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            # T4G family - Graviton2 (ARM), cheapest option (~20% savings)
            - "t4g.small"     # 2 vCPU, 2GB RAM, ~11 pods - CHEAPEST (ARM)
            - "t4g.medium"    # 2 vCPU, 4GB RAM, ~17 pods - Medium workload (ARM)
            # T3 family - x86_64 fallback for compatibility
            - "t3a.small"     # 2 vCPU, 2GB RAM, ~11 pods - x86_64 fallback
            - "t3.small"      # 2 vCPU, 2GB RAM, ~11 pods - x86_64 fallback
            - "t3a.medium"    # 2 vCPU, 4GB RAM, ~17 pods - x86_64 fallback
            - "t3.medium"     # 2 vCPU, 4GB RAM, ~17 pods - x86_64 fallback
            # Karpenter will prefer Graviton (t4g) instances when compatible
            # Limits ({{ karpenter_limits_cpu }} vCPU, {{ karpenter_limits_memory }}) ensure cost control

  # Limits for this NodePool (from config.yaml)
  limits:
    cpu: "{{ karpenter_limits_cpu }}"      # Maximum vCPUs across all nodes in this pool
    memory: {{ karpenter_limits_memory }}   # Maximum memory across all nodes in this pool

  # Disruption settings (consolidation, expiration, etc)
  disruption:
    # Consolidation: Replace underutilized nodes with cheaper/smaller ones
    consolidationPolicy: {{ karpenter_consolidation_policy }}

    # Consolidate after configured TTL seconds
    consolidateAfter: {{ karpenter_ttl_seconds }}s

    # Budget for disruptions (from config.yaml)
    budgets:
      - nodes: "{{ karpenter_disruption_budget }}"

  # Weight for scheduling priority (higher = preferred)
  weight: 10
