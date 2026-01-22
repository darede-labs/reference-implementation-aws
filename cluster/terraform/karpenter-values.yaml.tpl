settings:
  clusterName: {{ cluster_name }}
  clusterEndpoint: {{ cluster_endpoint }}
  interruptionQueue: {{ karpenter_queue_name }}

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: {{ karpenter_iam_role_arn }}
