# YAS DevOps Setup Guide

This guide explains the DevOps architecture and how to use the automated CI/CD pipelines for the YAS project.

## Overview

The YAS project uses:
- **CI/CD**: GitHub Actions (not Jenkins)
- **Container Registry**: Docker Hub
- **Container Orchestration**: Kubernetes (Minikube or self-managed cluster)
- **Image Tagging Strategy**: 
  - For all branches: `{commit_id}` (short SHA)
  - For main branch: `latest`

## Prerequisites

### Local Development Setup

1. **Minikube** (for local K8s environment)
   ```bash
   # Install Minikube: https://minikube.sigs.k8s.io/docs/start/
   minikube start --disk-size='40000mb' --memory='16g'
   
   # Enable ingress addon
   minikube addons enable ingress
   ```

2. **kubectl** (K8s CLI)
   ```bash
   # Install kubectl: https://kubernetes.io/docs/tasks/tools/
   ```

3. **Docker**
   ```bash
   # Install Docker: https://docs.docker.com/engine/install/
   ```

### GitHub Repository Setup

Set the following secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

- `DOCKER_HUB_USERNAME`: Your Docker Hub username
- `DOCKER_HUB_PASSWORD`: Your Docker Hub personal access token
- `KUBECONFIG`: Base64-encoded kubeconfig file (for GitHub Actions to connect to K8s cluster)
  ```bash
  cat ~/.kube/config | base64 | xclip -selection clipboard
  ```

## CI/CD Workflow

### 1. Continuous Integration (CI)

**Trigger**: Push to any branch or Pull Request to main

**What happens**:
1. Tests are run (unit tests, SonarCloud analysis, Snyk security scan)
2. Docker images are built with tag = commit ID (short SHA)
3. Images are pushed to Docker Hub

**Image tags created**:
- `docker run {branch_name}`: `{commit_id}` (e.g., `dev_tax_service`: `abc1234`)
- `main` branch: also pushes `latest` tag

### 2. Continuous Deployment (CD)

#### Developer Build (Manual Deployment)

Use the `Developer Build CD` workflow to deploy selective services with different branch configurations.

**How to trigger**:
1. Go to GitHub Actions → `Developer Build CD`
2. Click `Run workflow`
3. Input the branch name for each service you want to test:
   - Leave default (`main`) for services you don't want to test
   - Enter your feature branch name for services you're testing
4. Click `Run workflow`

**Example**: Testing tax service from branch `dev_tax_service`
- `tax_branch`: `dev_tax_service`
- Other branches: `main` (default)

**What happens**:
1. Workflow resolves image tags for all branches
2. K8s deployments are updated with the new images
3. Pods are restarted with new images
4. Service endpoints are provided

**Access your deployment**:
1. Get the NodePort for each service:
   ```bash
   kubectl get svc -n yas-dev
   ```

2. Add entries to `/etc/hosts` on your machine:
   ```
   {worker_node_ip} api.yas.local
   {worker_node_ip} storefront.yas.local
   {worker_node_ip} backoffice.yas.local
   ```

3. Access services:
   - Storefront: `http://storefront.yas.local:30018`
   - Backoffice: `http://backoffice.yas.local:30019`
   - Cart API: `http://api.yas.local:30001`
   - Other microservices on respective ports (30001-30020)

## Service Architecture

### Services and Default Ports

Java Microservices (NodePort 30001-30015 + 30020):
- cart: 30001
- customer: 30002
- inventory: 30003
- location: 30004
- media: 30005
- order: 30006
- payment: 30007
- payment-paypal: 30008
- product: 30009
- promotion: 30010
- rating: 30011
- recommendation: 30012
- search: 30013
- tax: 30014
- webhook: 30015
- sampledata: 30020

BFF Services (Backend for Frontend):
- backoffice-bff: 30016
- storefront-bff: 30017

Frontend (Next.js):
- storefront: 30018 (port 3000)
- backoffice: 30019 (port 3000)

## Initial K8s Deployment

### 1. Deploy Infrastructure

If you don't have infrastructure services (PostgreSQL, Elasticsearch, Kafka) running, deploy them first:

```bash
cd k8s/deploy
./setup-keycloak.sh
./setup-redis.sh
./setup-cluster.sh
```

### 2. Deploy YAS Application Services

```bash
# Deploy applications
kubectl apply -f yas-apps/yas-deployment.yaml

# Or using Helm (if using Helm approach)
helm install yas-apps ./k8s/charts/yas
```

### 3. Verify Deployments

```bash
# Check all deployments
kubectl get deployments -n yas-dev

# Check all services
kubectl get svc -n yas-dev

# Check pods
kubectl get pods -n yas-dev

# View logs
kubectl logs -n yas-dev deployment/cart -f
```

## Cleanup

### Delete Development Deployment

Use the `Cleanup Developer Deployment` workflow:

1. Go to GitHub Actions → `Cleanup Developer Deployment`
2. Click `Run workflow`
3. Type `DELETE` in the confirmation field
4. Click `Run workflow`

Or via kubectl:
```bash
kubectl delete namespace yas-dev
```

## Troubleshooting

### Images not pulling from Docker Hub

```bash
# Create secret for Docker Hub auth
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=$DOCKER_HUB_USERNAME \
  --docker-password=$DOCKER_HUB_PASSWORD \
  --docker-email=your@email.com \
  -n yas-dev

# Update deployments to use the secret (add imagePullSecrets)
```

### Pods stuck in pending state

```bash
# Check pod events
kubectl describe pod <pod-name> -n yas-dev

# Check node resources
kubectl top nodes
kubectl top pods -n yas-dev
```

### Service connectivity issues

```bash
# Check if services are running
kubectl get svc -n yas-dev

# Test connectivity between services
kubectl exec -n yas-dev <pod-name> -- curl http://cart:8000/actuator/health
```

## Environment Configuration

### Application Properties

Services use Spring Cloud Config. Set these environment variables:

```yaml
SPRING_PROFILES_ACTIVE: "kube"
DATABASE_USERNAME: postgres
DATABASE_PASSWORD: password
DATABASE_HOST: postgres.postgres  # Service DNS name
DATABASE_PORT: 5432
```

### Service Discovery

In K8s, services are discovered by DNS name:
- Within namespace: `{service-name}`
- Cross-namespace: `{service-name}.{namespace}.svc.cluster.local`

Example in `cart` service:
```
http://customer:8000  # Calls customer service
```

## Scaling Services

```bash
# Scale cart service to 3 replicas
kubectl scale deployment cart --replicas=3 -n yas-dev

# Check scaling
kubectl get deployment cart -n yas-dev
```

## Updating Resources

### Update service image

```bash
kubectl set image deployment/cart cart=yourusername/yas-cart:v1.2.3 -n yas-dev --record
```

### Update resource limits

Edit the deployment:
```bash
kubectl edit deployment cart -n yas-dev
```

## Next Steps

1. **Set up monitoring**: Configure Prometheus and Grafana
2. **Enable auto-scaling**: Configure HPA (Horizontal Pod Autoscaler)
3. **Setup ingress**: Configure Nginx/Traefik ingress for better routing
4. **Enable CI/CD for infrastructure**: Add CI/CD for Terraform/Helm charts

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/)
- [Docker Hub](https://hub.docker.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
