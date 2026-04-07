#!/bin/bash

# YAS K8s Application Deployment Script
# This script helps deploy the YAS application services to Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${1:-yas-dev}"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}YAS Application Deployment Script${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo -e "${RED}Error: kubeconfig not found at $KUBECONFIG_PATH${NC}"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG=$KUBECONFIG_PATH

echo -e "${BLUE}Step 1: Checking K8s cluster connectivity...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓ K8s cluster is accessible${NC}"
else
    echo -e "${RED}✗ Cannot connect to K8s cluster${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Creating namespace '${NAMESPACE}'...${NC}"
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace ${NAMESPACE} already exists${NC}"
else
    kubectl create namespace "$NAMESPACE"
    echo -e "${GREEN}✓ Namespace ${NAMESPACE} created${NC}"
fi

echo ""
echo -e "${BLUE}Step 3: Deploying YAS applications...${NC}"
kubectl apply -f yas-deployment.yaml -n "$NAMESPACE"
echo -e "${GREEN}✓ Applications deployed${NC}"

echo ""
echo -e "${BLUE}Step 4: Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment --all -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo -e "${BLUE}Step 5: Deployment Status${NC}"
kubectl get deployments -n "$NAMESPACE"

echo ""
echo -e "${BLUE}Step 6: Service Information${NC}"
echo -e "${YELLOW}Services (NodePort):${NC}"
kubectl get svc -n "$NAMESPACE" --no-headers | awk '{printf "  %-30s\t%-10s\t%-15s\n", $1, $3, $5}'

echo ""
echo -e "${BLUE}Step 7: Pod Status${NC}"
kubectl get pods -n "$NAMESPACE" --no-headers | awk '{printf "  %-30s\t%-15s\t%-10s\n", $1, $3, $5}'

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Add entries to /etc/hosts:"
echo "   {worker_node_ip} api.yas.local"
echo "   {worker_node_ip} storefront.yas.local"
echo "   {worker_node_ip} backoffice.yas.local"
echo ""
echo "2. Access services:"
echo "   Storefront: http://storefront.yas.local:30018"
echo "   Backoffice: http://backoffice.yas.local:30019"
echo ""
echo "3. View logs:"
echo "   kubectl logs -n ${NAMESPACE} -f deployment/cart"
echo ""
echo "4. Get pod details:"
echo "   kubectl get pods -n ${NAMESPACE} -o wide"
echo ""
