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

        # Instance category: T (burstable) and M (general purpose)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "m"]

        # Instance generation: 3+ for better performance
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]

        # Specific instance types - expanded for higher pod capacity
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            # T3 family - burstable, cost-effective (~17-58 pods)
            - "t3a.medium"    # 2 vCPU, 4GB RAM, ~17 pods
            - "t3.medium"     # 2 vCPU, 4GB RAM, ~17 pods
            - "t3a.large"     # 2 vCPU, 8GB RAM, ~35 pods
            - "t3.large"      # 2 vCPU, 8GB RAM, ~35 pods
            - "t3a.xlarge"    # 4 vCPU, 16GB RAM, ~58 pods
            - "t3.xlarge"     # 4 vCPU, 16GB RAM, ~58 pods
            # M5 family - general purpose, stable workloads (~29-58 pods)
            - "m5.large"      # 2 vCPU, 8GB RAM, ~29 pods
            - "m5.xlarge"     # 4 vCPU, 16GB RAM, ~58 pods
            - "m5a.large"     # 2 vCPU, 8GB RAM, ~29 pods
            - "m5a.xlarge"    # 4 vCPU, 16GB RAM, ~58 pods
            # M6i family - latest generation (~29-58 pods)
            - "m6i.large"     # 2 vCPU, 8GB RAM, ~29 pods
            - "m6i.xlarge"    # 4 vCPU, 16GB RAM, ~58 pods

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
