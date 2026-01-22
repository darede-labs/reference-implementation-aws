# ${{ values.name }}

${{ values.description }}

## Stack

- **Language:** Go 1.21
- **Framework:** Gin
- **Metrics:** Prometheus Client
- **Logging:** Structured JSON

## Local Development

### Prerequisites

- Go 1.21+

### Setup

```bash
# Install dependencies
go mod download

# Set environment variables
export APP_NAME="${{ values.name }}"
export APP_DESCRIPTION="${{ values.description }}"
export PORT=8080

# Run locally
go run cmd/api/main.go
```

### Test Endpoints

```bash
# Health check
curl http://localhost:8080/health

# Readiness check
curl http://localhost:8080/ready

# Root endpoint
curl http://localhost:8080/

# Prometheus metrics
curl http://localhost:8080/metrics
```

### Build Binary

```bash
# Build for local system
go build -o bin/api cmd/api/main.go

# Run the binary
./bin/api

# Build for Linux (for Docker)
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/api-linux cmd/api/main.go
```

## Docker Build

```bash
# Build image
docker build -t ${{ values.name }}:latest .

# Run container
docker run -d -p 8080:8080 \
  -e APP_NAME=${{ values.name }} \
  -e APP_DESCRIPTION="${{ values.description }}" \
  ${{ values.name }}:latest

# Test
curl http://localhost:8080/health
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

## Health Checks

- **Liveness:** `GET /health` - Returns 200 if service is alive
- **Readiness:** `GET /ready` - Returns 200 if service is ready to accept traffic

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APP_NAME` | Yes | `microservice` | Application name |
| `APP_DESCRIPTION` | No | `Go microservice` | Application description |
| `PORT` | No | `8080` | Port to listen on |

## Project Structure

```
.
├── cmd/
│   └── api/
│       └── main.go          # Application entry point
├── internal/
│   └── health/              # Health check handlers (optional)
├── Dockerfile
├── go.mod
├── go.sum
└── README.md
```

## Contributing

1. Create feature branch from `main`
2. Make changes
3. Run tests: `go test ./...`
4. Create Pull Request
5. Wait for CI/CD checks
6. Merge after approval

## License

MIT
