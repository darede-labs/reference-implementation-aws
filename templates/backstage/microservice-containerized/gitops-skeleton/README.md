# ${{ values.name }} - GitOps Repository

This repository contains the Kubernetes manifests for `${{ values.name }}`.

## Structure

```
.
├── manifests/
│   ├── namespace.yaml       # Namespace definition
│   ├── deployment.yaml      # Deployment with app containers
│   ├── service.yaml         # ClusterIP service
│   ├── ingress.yaml         # ALB Ingress (if exposed)
│   └── servicemonitor.yaml  # Prometheus ServiceMonitor
└── .argocd/
    └── application.yaml     # ArgoCD Application manifest
```

## Deployment

This application is deployed using **ArgoCD** with GitOps principles.

### How It Works

1. Application code is in the `${{ values.gitHubOrg }}/${{ values.name }}` repository
2. CI/CD pipeline builds Docker image and pushes to ECR
3. Pipeline updates `manifests/deployment.yaml` with new image tag in this repo
4. ArgoCD detects the change and automatically syncs to the cluster

### Sync Policy

- **Automated:** Changes are automatically deployed
- **Prune:** Resources removed from Git are deleted from cluster
- **Self-Heal:** Cluster state is corrected if manually modified

## Monitoring

### Prometheus Metrics

The `ServiceMonitor` resource enables Prometheus to scrape metrics from the `/metrics` endpoint.

View metrics in Grafana:
- Dashboard: https://grafana.${{ values.baseDomain }}/d/service-overview?var-namespace=${{ values.namespace }}&var-app=${{ values.name }}

### Logs

Logs are collected by Promtail and sent to Loki.

View logs in Grafana:
- Explorer: https://grafana.${{ values.baseDomain }}/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"${{ values.namespace }}\",app_kubernetes_io_name=\"${{ values.name }}\"}"}]

## Manual Operations

### Sync Application

```bash
argocd app sync ${{ values.name }}
```

### Check Application Status

```bash
argocd app get ${{ values.name }}
```

### View Logs

```bash
kubectl logs -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }} --tail=100 -f
```

### Scale Deployment

```bash
kubectl scale deployment ${{ values.name }} -n ${{ values.namespace }} --replicas=3
```

**Note:** Manual scaling will be reverted by ArgoCD's self-heal. To persist, update `manifests/deployment.yaml`.

## Troubleshooting

### Application Not Syncing

1. Check ArgoCD application status:
   ```bash
   argocd app get ${{ values.name }}
   ```

2. Check for sync errors:
   ```bash
   argocd app diff ${{ values.name }}
   ```

### Pods Not Starting

1. Check pod status:
   ```bash
   kubectl get pods -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }}
   ```

2. Describe pod:
   ```bash
   kubectl describe pod -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }}
   ```

3. Check pod logs:
   ```bash
   kubectl logs -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }}
   ```

### Service Not Accessible

1. Check service:
   ```bash
   kubectl get svc -n ${{ values.namespace }} ${{ values.name }}
   ```

2. Check endpoints:
   ```bash
   kubectl get endpoints -n ${{ values.namespace }} ${{ values.name }}
   ```

{% if values.exposure == 'public' or values.exposure == 'internal' %}
3. Check ingress:
   ```bash
   kubectl get ingress -n ${{ values.namespace }} ${{ values.name }}
   kubectl describe ingress -n ${{ values.namespace }} ${{ values.name }}
   ```

4. Check ALB:
   ```bash
   aws elbv2 describe-load-balancers --region ${{ values.awsRegion }}
   ```
{% endif %}

## Security

- Container runs as non-root user
- Resource limits enforced
- Health checks configured
- Network policies (if implemented)
- TLS termination at ALB (if exposed)

## Infrastructure Dependencies

{% if values.needsDatabase == 'yes' %}
### Database (RDS)

- **Type:** PostgreSQL (or MySQL)
- **Size:** ${{ values.databaseSize }}
- **Provisioned via:** Crossplane
- **Connection:** Check secret `${{ values.name }}-db-secret` in namespace `${{ values.namespace }}`

```bash
kubectl get secret ${{ values.name }}-db-secret -n ${{ values.namespace }} -o yaml
```
{% endif %}

{% if values.needsBucket == 'yes' %}
### S3 Bucket

- **Provisioned via:** Crossplane
- **Bucket name:** Check Crossplane Claim status

```bash
kubectl get s3bucketclaim ${{ values.name }}-bucket -n ${{ values.namespace }} -o yaml
```
{% endif %}

## Owner

**Team:** ${{ values.owner }}

For questions or issues, contact the team in Backstage or via your team's communication channel.
