# ${{ values.name }}

${{ values.description }}

## Stack

- **Language:** Python 3.11
- **Framework:** FastAPI
- **Metrics:** Prometheus Client
- **Logging:** Structured JSON

## Local Development

### Prerequisites

- Python 3.11+
- pip

### Setup

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export APP_NAME="${{ values.name }}"
export APP_DESCRIPTION="${{ values.description }}"
export PORT=8000

# Run locally
uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

### Test Endpoints

```bash
# Health check
curl http://localhost:8000/health

# Readiness check
curl http://localhost:8000/ready

# Root endpoint
curl http://localhost:8000/

# Prometheus metrics
curl http://localhost:8000/metrics
```

## Docker Build

```bash
# Build image
docker build -t ${{ values.name }}:latest .

# Run container
docker run -d -p 8000:8000 \
  -e APP_NAME=${{ values.name }} \
  -e APP_DESCRIPTION="${{ values.description }}" \
  ${{ values.name }}:latest

# Test
curl http://localhost:8000/health
```

## Deployment

This application is deployed via GitOps using ArgoCD. The Kubernetes manifests are in the `${{ values.name }}-gitops` repository.

### CI/CD

Automated CI/CD pipeline:
1. Code push to `main` branch
2. Docker image built and pushed to ECR
3. GitOps repository updated with new image tag
4. ArgoCD syncs and deploys to Kubernetes

### Monitoring

- **Logs:** https://grafana.${{ values.baseDomain }}/explore (Loki)
- **Metrics:** https://grafana.${{ values.baseDomain }} (Prometheus)
- **Dashboards:** https://grafana.${{ values.baseDomain }}/d/service-overview

## API Documentation

FastAPI provides interactive API documentation:

- **Swagger UI:** http://localhost:8000/docs
- **ReDoc:** http://localhost:8000/redoc

## Health Checks

- **Liveness:** `GET /health` - Returns 200 if service is alive
- **Readiness:** `GET /ready` - Returns 200 if service is ready to accept traffic

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APP_NAME` | Yes | `microservice` | Application name |
| `APP_DESCRIPTION` | No | `Python microservice` | Application description |
| `PORT` | No | `8000` | Port to listen on |

## Contributing

1. Create feature branch from `main`
2. Make changes
3. Run tests
4. Create Pull Request
5. Wait for CI/CD checks
6. Merge after approval

## License

MIT
