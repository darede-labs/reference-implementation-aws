# ${{ values.name }}

${{ values.description }}

## Overview

- **Owner:** ${{ values.owner }}
- **Runtime:** ${{ values.runtime }}
- **Port:** ${{ values.port }}
- **Namespace:** ${{ values.namespace }}

## Development

```bash
# Install dependencies
npm install

# Run in development mode (with hot reload)
npm run dev

# Run in production mode
npm start
```

## Endpoints

- `GET /` - Service information
- `GET /health` - Health check
- `GET /ready` - Readiness check{% if values.enableMetrics %}
- `GET /metrics` - Prometheus metrics{% endif %}

## Docker

```bash
# Build image
docker build -t ${{ values.name }}:latest .

# Run container
docker run -p ${{ values.port }}:${{ values.port }} ${{ values.name }}:latest

# Test health
curl http://localhost:${{ values.port }}/health
```

## Deployment

This service is deployed automatically via GitHub Actions:

1. Push to `main` branch
2. GitHub Actions builds and pushes image to ECR
3. Image tag is updated in GitOps repository
4. ArgoCD detects change and deploys to Kubernetes

## Observability

### Logs

View logs in Grafana:
[View Logs](https://grafana.${{ values.baseDomain }}/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"${{ values.namespace }}\",app_kubernetes_io_name=\"${{ values.name }}\"}"}])

### Metrics

View metrics dashboard:
[View Dashboard](https://grafana.${{ values.baseDomain }}/d/service-overview?var-namespace=${{ values.namespace }}&var-app=${{ values.name }})

### Structured Logging

This service uses JSON-structured logging. All log entries include:

- `level`: Log level (info, error, etc.)
- `msg`: Human-readable message
- `timestamp`: ISO 8601 timestamp
- `hostname`: Pod hostname
- `service`: Service name

Example log entry:
```json
{
  "level": "info",
  "msg": "Request completed",
  "timestamp": "2024-01-20T10:30:00.000Z",
  "hostname": "pod-abc123",
  "service": "${{ values.name }}",
  "method": "GET",
  "path": "/",
  "status": 200,
  "duration_ms": 15
}
```

## Configuration

Environment variables:

- `PORT`: HTTP port (default: ${{ values.port }})
- `APP_VERSION`: Application version (default: 1.0.0)

## CI/CD

### Prerequisites

Add these secrets to your GitHub repository:

- `AWS_ROLE_ARN`: IAM role ARN for GitHub Actions OIDC
- `GITOPS_TOKEN`: GitHub token for updating GitOps repository

### Pipeline Steps

1. **Build & Push**: Build Docker image and push to ECR
2. **Update GitOps**: Update image tag in `${{ env.GITOPS_REPO }}`
3. **ArgoCD Sync**: ArgoCD automatically deploys changes

## Troubleshooting

### Logs not appearing in Grafana

1. Check Promtail is running:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=promtail
   ```

2. Verify pod labels:
   ```bash
   kubectl get pod -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }} -o jsonpath='{.items[0].metadata.labels}'
   ```

### Service not deploying

1. Check ArgoCD sync status:
   ```bash
   argocd app get ${{ values.name }}
   ```

2. Check pod status:
   ```bash
   kubectl get pods -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }}
   ```

3. Check pod logs:
   ```bash
   kubectl logs -n ${{ values.namespace }} -l app.kubernetes.io/name=${{ values.name }}
   ```

## License

MIT
