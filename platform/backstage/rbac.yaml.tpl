# Backstage RBAC for Kubernetes Plugin
# Source: config.yaml
# DO NOT EDIT MANUALLY - regenerate with: scripts/render-templates.sh
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backstage-reader
  labels:
    app.kubernetes.io/name: backstage
    app.kubernetes.io/component: rbac
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - limitranges
      - namespaces
      - resourcequotas
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - apps
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - autoscaling
    resources:
      - horizontalpodautoscalers
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - batch
    resources:
      - jobs
      - cronjobs
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backstage-reader-binding
  labels:
    app.kubernetes.io/name: backstage
    app.kubernetes.io/component: rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: backstage-reader
subjects:
  - kind: ServiceAccount
    name: backstage
    namespace: backstage
