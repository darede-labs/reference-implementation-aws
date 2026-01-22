# GitOps Separate Repository Implementation

## 📋 Executive Summary

Successfully implemented the **"1 app = 1 repo"** pattern for GitOps repositories, creating a separate repository for the `hello-world-e2e` application with full CI/CD integration, ArgoCD automatic sync, and HTTPS access via NLB-terminated TLS.

---

## ✅ What Was Implemented

### 1. **Automated Repository Creation Script**
- **Script**: `scripts/create-gitops-repo.sh`
- **Purpose**: Automate the creation of GitOps repositories for applications
- **Features**:
  - Creates GitHub repository via `gh` CLI
  - Generates Kubernetes manifests (Deployment, Service, Ingress)
  - Creates ArgoCD Application manifest
  - Generates comprehensive README
  - Handles directory structure and best practices

### 2. **GitOps Repository Structure**
- **Repository**: `https://github.com/darede-labs/hello-world-e2e`
- **Structure**:
  ```
  hello-world-e2e/
  ├── manifests/
  │   ├── deployment.yaml    # Kubernetes Deployment with 2 replicas
  │   ├── service.yaml       # ClusterIP Service
  │   └── ingress.yaml       # HTTPS Ingress (NLB-terminated TLS)
  ├── argocd-application.yaml # ArgoCD Application manifest
  ├── README.md               # Comprehensive documentation
  └── .gitignore              # Git ignore rules
  ```

### 3. **Kubernetes Manifests**

#### **Deployment**
- **Replicas**: 2
- **Image**: `948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-world-e2e:main`
- **Resources**:
  - **Requests**: 100m CPU, 128Mi RAM
  - **Limits**: 500m CPU, 512Mi RAM
- **Health Checks**:
  - **Liveness Probe**: `/health` endpoint
  - **Readiness Probe**: `/ready` endpoint
- **Labels**:
  - `app.kubernetes.io/name: hello-world-e2e`
  - `app.kubernetes.io/component: backend`
  - `app.kubernetes.io/part-of: platform-services`
  - `app.kubernetes.io/managed-by: argocd`

#### **Service**
- **Type**: ClusterIP
- **Port**: 80 (maps to container port 3000)
- **Selector**: `app.kubernetes.io/name: hello-world-e2e`

#### **Ingress**
- **Host**: `hello-world-e2e.timedevops.click`
- **Annotations**:
  - `kubernetes.io/ingress.class: nginx`
  - `nginx.ingress.kubernetes.io/backend-protocol: HTTP`
  - `external-dns.alpha.kubernetes.io/hostname: hello-world-e2e.timedevops.click`
- **TLS**: Terminated at NLB (no `spec.tls` section)
- **No SSL Redirect Annotations**: Fixed 308 redirect loop

### 4. **ArgoCD Application**
- **Name**: `hello-world-e2e`
- **Namespace**: `argocd`
- **Source**:
  - **Repo**: `https://github.com/darede-labs/hello-world-e2e.git`
  - **Revision**: `main`
  - **Path**: `manifests`
- **Destination**:
  - **Server**: `https://kubernetes.default.svc`
  - **Namespace**: `default`
- **Sync Policy**:
  - **Automated**: `true`
  - **Prune**: `true` (removes resources not in Git)
  - **Self-Heal**: `true` (reverts manual changes)
  - **CreateNamespace**: `true`
- **Status**: ✅ **Synced** and **Healthy**

### 5. **ECR Image Management**
- **Repository**: `hello-world-e2e`
- **Image Tag**: `main`
- **Image Scanning**: Enabled
- **Encryption**: AES256
- **IAM Permissions**: Nodes have `AmazonEC2ContainerRegistryReadOnly` policy

### 6. **Application Endpoints**
- **Base URL**: `https://hello-world-e2e.timedevops.click`
- **Health Check**: `https://hello-world-e2e.timedevops.click/health` ✅ Working
- **Readiness Check**: `https://hello-world-e2e.timedevops.click/ready` ✅ Working
- **Root Endpoint**: `https://hello-world-e2e.timedevops.click/` ✅ Working
- **Metrics**: `https://hello-world-e2e.timedevops.click/metrics` (Prometheus format)

---

## 🔧 Technical Details

### **Image Build and Push**
```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 --profile darede | \
  docker login --username AWS --password-stdin 948881762705.dkr.ecr.us-east-1.amazonaws.com

# Build and push
docker buildx build --platform linux/amd64 --push \
  -t 948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-world-e2e:main .
```

### **ArgoCD Sync**
```bash
# Apply ArgoCD Application
kubectl apply -f argocd-application.yaml

# Check sync status
kubectl get application hello-world-e2e -n argocd

# Force sync (if needed)
kubectl -n argocd annotate application hello-world-e2e \
  argocd.argoproj.io/refresh=normal --overwrite
```

### **Testing**
```bash
# Local port-forward test
kubectl port-forward -n default svc/hello-world-e2e 18080:80
curl -s http://localhost:18080/health | jq .

# External HTTPS test
curl -sk https://hello-world-e2e.timedevops.click/health | jq .
```

---

## 🐛 Issues Resolved

### **Issue #1: ImagePullBackOff**
- **Root Cause**: ECR image tag cache propagation delay
- **Solution**: Deleted pod to force recreation with fresh image pull

### **Issue #2: 308 Permanent Redirect Loop**
- **Root Cause**: Ingress had `nginx.ingress.kubernetes.io/ssl-redirect: "true"` annotation
- **Impact**: All HTTPS requests returned `308 Permanent Redirect` HTML
- **Solution**: Removed `ssl-redirect` and `force-ssl-redirect` annotations
- **Explanation**: When TLS is terminated at the NLB, the NGINX Ingress Controller receives plain HTTP requests with `X-Forwarded-Proto: https` header. The `ssl-redirect` annotation causes NGINX to redirect to HTTPS, creating a loop.
- **Correct Configuration**:
  - NLB terminates TLS (ACM certificate)
  - NGINX ConfigMap has `use-forwarded-headers: "true"`
  - Ingress has NO `ssl-redirect` annotations
  - Ingress has NO `spec.tls` section

---

## 📊 Validation Results

### **ArgoCD Status**
```
NAME              SYNC STATUS   HEALTH STATUS
hello-world-e2e   Synced        Healthy
```

### **Pods Status**
```
NAME                               READY   STATUS    RESTARTS   AGE
hello-world-e2e-59f567697f-f2l2p   1/1     Running   0          10m
hello-world-e2e-59f567697f-gtz6d   1/1     Running   0          10m
```

### **Endpoint Tests**
```json
// /health
{
  "status": "healthy",
  "timestamp": "2026-01-21T13:41:42.445Z"
}

// /ready
{
  "status": "ready",
  "timestamp": "2026-01-21T13:41:43.165Z"
}

// /
{
  "service": "hello-world-e2e",
  "description": "Microservice deployed via GitOps",
  "version": "1.0.0",
  "timestamp": "2026-01-21T13:41:43.809Z",
  "hostname": "hello-world-e2e-59f567697f-f2l2p"
}
```

---

## 🎯 Key Learnings

### **1. GitOps Repository Pattern**
- ✅ **"1 app = 1 repo"** provides clear ownership and isolation
- ✅ Separates application code from Kubernetes manifests
- ✅ Enables independent versioning of infrastructure and application
- ✅ Simplifies ArgoCD Application management

### **2. Ingress TLS Configuration**
- ❌ **NEVER** use `ssl-redirect` annotations when TLS is terminated at the load balancer
- ❌ **NEVER** define `spec.tls` in Ingress when using NLB TLS termination
- ✅ **ALWAYS** use `use-forwarded-headers: true` in NGINX ConfigMap
- ✅ **ALWAYS** test with `curl -sk https://...` to verify HTTPS is working

### **3. ArgoCD Sync Strategies**
- ✅ `automated.prune: true` removes resources deleted from Git
- ✅ `automated.selfHeal: true` reverts manual changes (drift prevention)
- ✅ `syncOptions: [CreateNamespace=true]` auto-creates target namespace
- ✅ `retry.limit: 5` with exponential backoff handles transient failures

### **4. ECR Image Management**
- ✅ Image tags should be immutable (use commit SHA or semantic versioning)
- ✅ Enable image scanning for security vulnerabilities
- ✅ Use lifecycle policies to clean up old images
- ✅ Nodes need `AmazonEC2ContainerRegistryReadOnly` policy

---

## 📝 Next Steps

### **Immediate**
1. ✅ **Update `create-gitops-repo.sh`** to not include SSL redirect annotations
2. ⏳ **Create CI/CD workflow** in application repository to:
   - Build Docker image
   - Push to ECR
   - Update `deployment.yaml` in GitOps repo with new image tag
3. ⏳ **Add Backstage integration** to auto-create GitOps repos for new applications

### **Short-term**
1. **Implement ApplicationSet** for auto-discovery of GitOps repositories
2. **Add Kyverno policies** to validate GitOps repository structure
3. **Create dashboard** in Grafana for application metrics
4. **Add alerts** for deployment failures and health check failures

### **Long-term**
1. **Migrate to FluxCD** (if needed) for GitOps CD
2. **Implement Progressive Delivery** with Flagger
3. **Add Canary Deployments** for zero-downtime releases
4. **Implement Multi-cluster GitOps** for production/staging separation

---

## 🔗 Related Documentation

- **TLS Configuration**: `docs/TLS-CONFIGURATION.md`
- **Manual Test Resolution**: `MANUAL-TEST-RESOLUTION-SUMMARY.md`
- **Critical Issues Analysis**: `CRITICAL-ISSUES-ANALYSIS.md`
- **E2E Bug Report**: `docs/E2E-BUG-REPORT.md`

---

## 👥 Team

- **Implemented by**: Platform Engineering Team
- **Date**: 2026-01-21
- **Version**: 1.0
- **Status**: ✅ **Production Ready**

---

**Note**: This implementation follows GitOps best practices and serves as a template for all future applications in the platform.
