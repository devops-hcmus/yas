# YAS Application K8s Manifests

This directory contains Kubernetes manifests for deploying YAS microservices.

## Contents

- `yas-deployment.yaml`: Complete K8s manifests for all YAS services (Deployments and Services)
- `deploy.sh`: Helper script to deploy all services with validation

## Prerequisites

1. **Kubernetes Cluster**
   - Minikube (for local development)
   - EKS, AKS, or self-managed K8s cluster

2. **kubectl** configured to access your cluster
   
3. **Docker Hub Account** with credentials configured in GitHub Secrets

## Quick Start

### Option 1: Using the Deploy Script

```bash
# Make script executable
chmod +x deploy.sh

# Deploy to default namespace (yas-dev)
./deploy.sh

# Deploy to custom namespace
./deploy.sh my-namespace
```

### Option 2: Manual Deployment

```bash
# Create namespace
kubectl create namespace yas-dev

# Deploy manifests
kubectl apply -f yas-deployment.yaml -n yas-dev

# Verify deployments
kubectl get deployments -n yas-dev
kubectl get svc -n yas-dev
kubernetes get pods -n yas-dev
```

## Service Configuration

### Java Microservices

All Java services are configured with:
- **Port**: 8000
- **Spring Profile**: `kube`
- **Health Checks**: 
  - Liveness: `/actuator/health/liveness`
  - Readiness: `/actuator/health/readiness`
- **Resources**:
  - Request: 256Mi memory, 100m CPU
  - Limit: 512Mi memory, 500m CPU

### Node.js Frontends

Frontend services (storefront, backoffice):
- **Port**: 3000
- **Resources**: Same as Java services

## Accessing Services

### Get Service Information

```bash
# List all services with ports
kubectl get svc -n yas-dev -o wide

# Example output:
# NAME                TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
# cart                NodePort   10.96.123.45    <none>        8000:30001/TCP   5m
# storefront          NodePort   10.96.123.46    <none>        3000:30018/TCP   5m
```

### Access via NodePort

For a local cluster (Minikube):
```bash
# Get Minikube IP
minikube ip  # e.g., 192.168.99.100

# Access service
curl http://192.168.99.100:30001/actuator/health
```

For a remote cluster:
```bash
# Get worker node IP
kubectl get nodes -o wide

# Access service (replace WORKER_IP with actual node IP)
curl http://WORKER_IP:30001/actuator/health
```

### Add DNS Entries (Optional)

Add to `/etc/hosts`:
```
192.168.99.100 api.yas.local
192.168.99.100 storefront.yas.local
192.168.99.100 backoffice.yas.local
```

Then access:
```bash
curl http://api.yas.local:30001/actuator/health
curl http://storefront.yas.local:30018
curl http://backoffice.yas.local:30019
```

## Viewing Logs

```bash
# View logs from a pod
kubectl logs -n yas-dev pod/cart-xyz123 -f

# View logs from a deployment
kubectl logs -n yas-dev deployment/cart -f

# View logs from all pods of a service
kubectl logs -n yas-dev -l app=cart -f
```

## Scaling Services

```bash
# Scale to 3 replicas
kubectl scale deployment cart --replicas=3 -n yas-dev

# Verify scaling
kubectl get deployment cart -n yas-dev
kubectl get pods -n yas-dev -l app=cart
```

## Updating Image

```bash
# Update deployment image
kubectl set image deployment/cart cart=yourusername/yas-cart:v1.2.3 -n yas-dev --record

# Or edit deployment
kubectl edit deployment cart -n yas-dev
```

## Environment Variables

### Database Configuration

Add these to your manifest if needed:
```yaml
env:
- name: DATABASE_HOST
  value: "postgres.postgres.svc.cluster.local"
- name: DATABASE_PORT
  value: "5432"
- name: DATABASE_USERNAME
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: username
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: password
```

### Kafka Configuration

```yaml
env:
- name: KAFKA_BOOTSTRAP_SERVERS
  value: "kafka-cluster.kafka.svc.cluster.local:9092"
```

### Service Discovery

Services are discovered by Kubernetes DNS:
```
{service-name}.{namespace}.svc.cluster.local
```

Example in cart service calling customer:
```
http://customer.yas-dev.svc.cluster.local:8000
```

Or within same namespace (simpler):
```
http://customer:8000
```

## Troubleshooting

### Pod stuck in Pending

```bash
# Check pod events
kubectl describe pod cart-xyz123 -n yas-dev

# Check node resources
kubectl top nodes
kubectl top pods -n yas-dev

# Check if images can be pulled
kubectl get events -n yas-dev --sort-by='.lastTimestamp'
```

### Service not responding

```bash
# Check if service is running
kubectl get svc cart -n yas-dev

# Check endpoint
kubectl get endpoints cart -n yas-dev

# Test connectivity from another pod
kubectl exec -n yas-dev deployment/storefront -- curl http://cart:8000/actuator/health
```

### Memory/CPU Issues

Increase limits in the manifest:
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

## Cleanup

```bash
# Delete all services in namespace
kubectl delete -f yas-deployment.yaml -n yas-dev

# Delete namespace (removes all resources)
kubectl delete namespace yas-dev
```

## Port Mapping

| Service | Port | NodePort |
|---------|------|----------|
| cart | 8000 | 30001 |
| customer | 8000 | 30002 |
| inventory | 8000 | 30003 |
| location | 8000 | 30004 |
| media | 8000 | 30005 |
| order | 8000 | 30006 |
| payment | 8000 | 30007 |
| payment-paypal | 8000 | 30008 |
| product | 8000 | 30009 |
| promotion | 8000 | 30010 |
| rating | 8000 | 30011 |
| recommendation | 8000 | 30012 |
| search | 8000 | 30013 |
| tax | 8000 | 30014 |
| webhook | 8000 | 30015 |
| backoffice-bff | 8000 | 30016 |
| storefront-bff | 8000 | 30017 |
| storefront | 3000 | 30018 |
| backoffice | 3000 | 30019 |
| sampledata | 8000 | 30020 |

## Related Documentation

- [DevOps Guide](../../docs/DEVOPS_GUIDE.md)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/)
