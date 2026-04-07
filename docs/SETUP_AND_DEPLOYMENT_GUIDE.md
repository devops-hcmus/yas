# YAS DevOps - Hướng Dẫn Cấu Hình & Triển Khai Chi Tiết

Tài liệu này cung cấp hướng dẫn chi tiết về cấu hình toàn diện, luồng hoạt động, ý nghĩa các file YAML, và cách triển khai hệ thống YAS.

---

## Mục Lục

1. [Kiến Trúc Tổng Quan](#kiến-trúc-tổng-quan)
2. [Cấu Hình GitHub Repository](#cấu-hình-github-repository)
3. [Cấu Hình Kubernetes Cluster](#cấu-hình-kubernetes-cluster) ⭐ **3 Ubuntu Server VMs or Minikube**
4. [Cấu Hình VM/Network](#cấu-hình-vmnetwork)
5. [Giải Thích Các File YAML](#giải-thích-các-file-yaml)
6. [Hướng Dẫn Triển Khai Từng Bước](#hướng-dẫn-triển-khai-từng-bước)
7. [Luồng Hoạt Động Chi Tiết](#luồng-hoạt-động-chi-tiết)
8. [Chạy & Kiểm Thử CI/CD](#chạy--kiểm-thử-cicd)
9. [Troubleshooting](#troubleshooting) ⭐ **+5 Issues cho 3-VM Cluster**
10. [Cheat Sheet](#cheat-sheet---lệnh-thường-dùng)

---

## Kiến Trúc Tổng Quan

```
┌─────────────────────────────────────────────────────────────────┐
│                     Developer Workflow                          │
│  1. Commit code → 2. Push branch → 3. CI triggers automatically │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  GitHub Actions - Automatic CI Pipeline │
        │  • Run tests                            │
        │  • Build Docker image                   │
        │  • Push to Docker Hub                   │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │        Docker Hub Registry              │
        │  Image: yourusername/yas-{service}:tag │
        │  Tags: {commit_id}, latest              │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Manual Trigger: Developer Build CD     │
        │  Input: Branches for each service       │
        │  Example: tax_branch=dev_tax_service   │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │     Kubernetes Deployment Update        │
        │  • Update image tags in deployments     │
        │  • Restart pods with new images         │
        │  • Run in namespace: yas-dev            │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │    Developer Access via NodePort        │
        │  • storefront: localhost:30018          │
        │  • backoffice: localhost:30019          │
        │  • APIs: localhost:30001-30020          │
        └─────────────────────────────────────────┘
```

---

## Cấu Hình GitHub Repository

### 1. Tạo GitHub Secrets

Để cho phép GitHub Actions push images lên Docker Hub và deploy lên K8s, bạn cần tạo 3 secrets.

**Bước 1: Vào Settings → Secrets and variables → Actions**

```
GitHub URL: https://github.com/{owner}/{repo}/settings/secrets/actions
```

**Bước 2: Tạo 3 secrets sau:**

#### Secret 1: DOCKER_HUB_USERNAME
- **Name**: `DOCKER_HUB_USERNAME`
- **Value**: Tên đăng nhập Docker Hub của bạn
- **Ví dụ**: `myusername`

#### Secret 2: DOCKER_HUB_PASSWORD
- **Name**: `DOCKER_HUB_PASSWORD`
- **Value**: Personal Access Token của Docker Hub (không phải password)
  
  **Cách tạo Docker Hub Token**:
  ```
  1. Vào https://hub.docker.com/settings/security
  2. Nhấp "New Access Token"
  3. Đặt tên: "github-actions"
  4. Chọn Permissions: "Read & Write"
  5. Copy token → Lưu vào Secret này
  ```

#### Secret 3: KUBECONFIG
- **Name**: `KUBECONFIG`
- **Value**: Base64-encoded kubeconfig file

  **Cách tạo KUBECONFIG Secret**:
  
  ```bash
  # Nếu dùng Minikube:
  minikube start
  cat ~/.kube/config | base64 | tr -d '\n'
  
  # Hoặc nếu dùng K8s cluster khác:
  cat ~/.kube/config | base64 | tr -d '\n'
  ```
  
  Sau đó copy kết quả và paste vào Secret.

**Verification**: Sau khi tạo secrets, bạn sẽ thấy:
```
✓ DOCKER_HUB_USERNAME
✓ DOCKER_HUB_PASSWORD
✓ KUBECONFIG
```

### 2. Cấu Hình Workflow Tokens

GitHub Actions cần GITHUB_TOKEN (auto-generated) để push code, nhưng kiểm tra rằng:

```
Settings → Actions → General → Workflow permissions
✓ Read and write permissions
✓ Allow GitHub Actions to create and approve pull requests
```

---

## Cấu Hình Kubernetes Cluster

### Tùy Chọn 1: 3 Ubuntu Server VMs (1 Master + 2 Worker) ⭐ **RECOMMENDED**

**Yêu Cầu Hệ Thống**:
- **Master Node**: Ubuntu 24 LTS, 8GB RAM, 4 CPU, 50GB Disk, IP: 192.168.1.10
- **Worker Node 1**: Ubuntu 24 LTS, 8GB RAM, 4 CPU, 50GB Disk, IP: 192.168.1.11
- **Worker Node 2**: Ubuntu 24 LTS, 8GB RAM, 4 CPU, 50GB Disk, IP: 192.168.1.12
- Tất cả 3 VMs phải ping được nhau trên LAN

**Setup Architecture**:
```
                    ┌─────────────────┐
                    │  Master Node    │
                    │ 192.168.1.10    │
                    │ (Control Plane) │
                    └────────┬────────┘
                      /      │      \
                     /       │       \
        ┌───────────┐  ┌────────────┐  ┌───────────┐
        │Worker Node│  │ Worker Node│  │  Optional │
        │192.168.1.11  │192.168.1.12   │   Node3   │
        │(Application) │(Application)  │(Persistent│
        └───────────┘  └────────────┘  │ Storage)  │
                                        └───────────┘
```

#### Phase 0: Pre-Setup (Trên tất cả 3 VMs)

**Bước 1: Update system & install Docker**

```bash
# SSH vào mỗi VM và chạy:
ssh ubuntu@192.168.1.10     # Master
# hoặc
ssh ubuntu@192.168.1.11     # Worker 1
# hoặc
ssh ubuntu@192.168.1.12     # Worker 2

# Sau khi SSH vào, chạy:
sudo apt-get update
sudo apt-get upgrade -y

# Cài Docker
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker ubuntu

# Khởi động Docker
sudo systemctl enable docker
sudo systemctl start docker

# Verify
docker --version
```

**Bước 2: Cấu hình network prerequisites**

```bash
# Trên tất cả 3 VMs:
sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

**Bước 3: Cài đặt Kubernetes tools**

```bash
# Trên tất cả 3 VMs:
curl -fsSLo /tmp/golang.key https://dl.google.com/linux/linux_signing_key.pub
sudo apt-key add /tmp/golang.key
sudo apt-get install -y apt-transport-https ca-certificates

# Add Kubernetes repository
echo "deb https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update

# Cài kubeadm, kubelet, kubectl
sudo apt-get install -y kubeadm=1.28.* kubelet=1.28.* kubectl=1.28.*
sudo apt-mark hold kubeadm kubelet kubectl

# Verify
kubeadm version
kubelet --version
kubectl version --client
```

#### Phase 1: Master Node Setup (192.168.1.10)

**Bước 1: Initialize Kubernetes cluster**

```bash
ssh ubuntu@192.168.1.10

# Khởi tạo cluster (pod network sẽ dùng Calico)
sudo kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --pod-network-cidr=10.244.0.0/16

# Sau initialization, copy kubeconfig
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Verify cluster initialized
kubectl cluster-info
kubectl get nodes
# Output: Master node sẽ ở status "NotReady" (chờ networking plugin)
```

**Bước 2: Cài đặt Calico networking plugin**

```bash
# Trên Master node:
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml

# Chờ operators được installed
kubectl wait --for=condition=available --timeout=300s deployment/tigera-operator -n tigera-operator

# Install Calico
kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 172.29.0.0/16
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Chờ tới khi Calico ready (~2-3 phút)
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s

# Verify
kubectl get nodes
# Output: Master phải ở "Ready"
```

**Bước 3: Lấy join token**

```bash
# Trên Master node, generate token để workers join
kubeadm token create --print-join-command

# Output ví dụ:
# kubeadm join 192.168.1.10:6443 \
#   --token 7ab2c8.1c5de5e8b3e2f5a6 \
#   --discovery-token-ca-cert-hash sha256:abc123...def456...

# Lưu command này, sẽ dùng trên Worker nodes
```

#### Phase 2: Worker Nodes Setup (192.168.1.11 & 192.168.1.12)

**Bước 1: Join cluster (trên cả 2 workers)**

```bash
# SSH vào Worker 1
ssh ubuntu@192.168.1.11

# Paste join command từ Master:
sudo kubeadm join 192.168.1.10:6443 \
  --token 7ab2c8.1c5de5e8b3e2f5a6 \
  --discovery-token-ca-cert-hash sha256:abc123...def456...

# Output: "This node has joined the cluster. ..."
```

```bash
# SSH vào Worker 2 (tương tự)
ssh ubuntu@192.168.1.12

# Paste join command từ Master:
sudo kubeadm join 192.168.1.10:6443 \
  --token 7ab2c8.1c5de5e8b3e2f5a6 \
  --discovery-token-ca-cert-hash sha256:abc123...def456...
```

**Bước 2: Verify cluster (trên Master node)**

```bash
ssh ubuntu@192.168.1.10

# Check all nodes
kubectl get nodes
# Output:
# NAME     STATUS   ROLES           AGE
# master   Ready    control-plane   5m
# worker1  Ready    <none>          2m
# worker2  Ready    <none>          1m

# Check all pods
kubectl get pods --all-namespaces
# Tất cả pods phải ở "Running" except pending

# Check calico status
kubectl get pods -n calico-system
# Output: Tất cả calico pods running
```

#### Phase 3: Setup kubeconfig cho Client Machine (máy dev)

**Bước 1: Copy kubeconfig từ Master**

```bash
# Trên Master node (192.168.1.10):
cat ~/.kube/config

# Copy toàn bộ output này
```

**Bước 2: Thêm kubeconfig vào client machine**

```bash
# Trên máy local (dev machine):
mkdir -p ~/.kube

# Paste kubeconfig từ trên vào file local:
cat > ~/.kube/config <<'EOF'
# <PASTE kubeconfig content here>
EOF

# Verify kết nối
kubectl cluster-info
kubectl get nodes
```

**Bước 3: Setup GitHub Secret KUBECONFIG**

```bash
# Trên máy local:
cat ~/.kube/config | base64 | tr -d '\n'

# Copy base64 output
# GitHub → Settings → Secrets → KUBECONFIG
# Paste base64 content vào Secret
```

---

### Tùy Chọn 2: Local Development với Minikube

**Yêu Cầu Hệ Thống**:
- OS: Linux, macOS, hoặc Windows
- RAM: Tối thiểu 16GB (khuyến nghị: 20GB+)
- Disk: 40GB trống
- Docker hoặc VirtualBox installed

**Bước 1: Cài đặt Minikube**

```bash
# macOS
brew install minikube

# Linux
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Windows
choco install minikube
```

**Bước 2: Khởi động Minikube**

```bash
# Khởi động với cấu hình phù hợp
minikube start \
  --disk-size='40000mb' \
  --memory='16g' \
  --cpus=4 \
  --driver=docker

# Hoặc sử dụng VirtualBox nếu không có Docker
minikube start \
  --disk-size='40000mb' \
  --memory='16g' \
  --cpus=4 \
  --driver=virtualbox

# Kiểm tra status
minikube status

# Output mong đợi:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
```

**Bước 3: Enable Ingress Add-on**

```bash
minikube addons enable ingress

# Kiểm tra add-ons
minikube addons list
```

**Bước 4: Cấu Hình KUBECONFIG**

```bash
# Minikube tự động tạo kubeconfig
# Kiểm tra:
cat ~/.kube/config

# Hoặc set explicit:
export KUBECONFIG=~/.kube/config

# Verify kết nối:
kubectl cluster-info
kubectl get nodes
```

### Tùy Chọn 3: Production K8s Cluster (AWS EKS, Azure AKS, GCP GKE)

**AWS EKS Example**:

```bash
# Cài đặt AWS CLI & eksctl
brew install awscli eksctl

# Tạo cluster
eksctl create cluster \
  --name yas-cluster \
  --region us-east-1 \
  --nodegroup-name yas-nodes \
  --node-type t3.medium \
  --nodes 2

# Xác minh kết nối
kubectl get nodes
kubectl cluster-info
```

**Azure AKS Example**:

```bash
# Tạo resource group
az group create --name yas-rg --location eastus

# Tạo AKS cluster
az aks create \
  --resource-group yas-rg \
  --name yas-cluster \
  --node-count 2 \
  --vm-set-type VirtualMachineScaleSets \
  --load-balancer-sku standard

# Cập nhật kubeconfig
az aks get-credentials \
  --resource-group yas-rg \
  --name yas-cluster
```

---

## Cấu Hình VM/Network

### 1. Cấu Hình Network cho 3 Ubuntu Server VMs ⭐ **RECOMMENDED**

**Kiểm tra Network Connectivity**

```bash
# Từ dev machine, ping đến tất cả 3 VMs:
ping 192.168.1.10   # Master
ping 192.168.1.11   # Worker 1
ping 192.168.1.12   # Worker 2

# Nếu không reach, kiểm tra firewall:
# - Mở port 6443 (Kubernetes API) trên Master
# - Mở port 10250 (kubelet) trên tất cả nodes
# - Mở ports 30000-32767 (NodePort range)
```

**Setup SSH Key-Based Authentication (Optional)**

```bash
# Trên dev machine, tạo SSH key:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/yas-vm -N ""

# Copy public key đến mỗi VM:
ssh-copy-id -i ~/.ssh/yas-vm ubuntu@192.168.1.10
ssh-copy-id -i ~/.ssh/yas-vm ubuntu@192.168.1.11
ssh-copy-id -i ~/.ssh/yas-vm ubuntu@192.168.1.12

# Test SSH no-password:
ssh -i ~/.ssh/yas-vm ubuntu@192.168.1.10 "echo Connected"
```

**Cấu hình /etc/hosts (trên dev machine)**

```bash
# Thêm vào /etc/hosts để dùng hostname thay vì IP:
echo "192.168.1.10 k8s-master" | sudo tee -a /etc/hosts
echo "192.168.1.11 k8s-worker1" | sudo tee -a /etc/hosts
echo "192.168.1.12 k8s-worker2" | sudo tee -a /etc/hosts

# Test:
ping k8s-master
ssh ubuntu@k8s-master
```

**Firewall Configuration** (nếu UFW enabled)

```bash
# Trên mỗi VM:
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 6443/tcp     # Kubernetes API
sudo ufw allow 10250/tcp    # Kubelet
sudo ufw allow 30000:32767/tcp  # NodePort range
sudo ufw allow 10251/tcp    # kube-scheduler
sudo ufw allow 10252/tcp    # kube-controller

# Enable UFW nếu chưa:
sudo ufw enable
sudo ufw status
```

### 2. Cấu Hình Network cho Minikube

**Nếu dùng Minikube**, cần cấu hình để access từ host machine:

```bash
# 1. Lấy Minikube IP
minikube ip
# Output: 192.168.49.2

# 2. Cấu hình port forwarding (nếu cần)
minikube tunnel

# 3. Thêm vào /etc/hosts (macOS/Linux)
echo "192.168.49.2 yas.local
192.168.49.2 api.yas.local
192.168.49.2 storefront.yas.local
192.168.49.2 backoffice.yas.local" | sudo tee -a /etc/hosts

# 4. Windows - Thêm vào C:\Windows\System32\drivers\etc\hosts:
# 192.168.49.2 yas.local
# 192.168.49.2 api.yas.local
```

**Cấu hình Resource Limits**:

```bash
# Kiểm tra resource hiện tại
minikube ssh
free -h  # RAM
df -h    # Disk

# Nếu cần scale up (stop cluster trước):
minikube stop
minikube delete
minikube start --memory=20g --disk-size=50gb
```

### 3. Cấu Hình Storage (Optional)

**Minikube**:
```bash
# Minikube mặc định dùng local storage
# Kiểm tra storage class:
kubectl get storageclass

# Nếu cần persistent volume:
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-yas-data
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
EOF
```

**3-VM Cluster**:
```bash
# Trên mỗi Worker node, tạo local storage path:
ssh ubuntu@k8s-worker1
mkdir -p /mnt/local-storage
sudo chown 1000:1000 /mnt/local-storage

# Repeat cho worker2

# Sau đó trên Master, create PersistentVolume:
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-worker1-data
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/local-storage"
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker1
EOF
```

---

## Giải Thích Các File YAML

### 1. File: `k8s/deploy/yas-apps/yas-deployment.yaml`

**Mục Đích**: Định nghĩa tất cả Kubernetes resources cho 20 YAS services

**Cấu Trúc**:

```yaml
# Phần 1: Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: yas-dev
---

# Phần 2: Deployment (lặp lại cho mỗi service)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart                    # Tên service
  namespace: yas-dev           # Namespace
  labels:
    app: cart
spec:
  replicas: 1                  # Số pod replicas
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
      - name: cart
        image: changeme/yas-cart:latest  # ← THAY ĐỔI: Thay "changeme" bằng Docker Hub username
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "kube"
        resources:
          requests:              # Minimum resources
            memory: "256Mi"
            cpu: "100m"
          limits:                # Maximum resources
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:           # Kiểm tra pod còn sống không
          httpGet:
            path: /actuator/health/liveness
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:          # Kiểm tra pod sẵn sàng nhận traffic
          httpGet:
            path: /actuator/health/readiness
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 5
---

# Phần 3: Service (lặp lại cho mỗi service)
apiVersion: v1
kind: Service
metadata:
  name: cart
  namespace: yas-dev
  labels:
    app: cart
spec:
  type: NodePort               # Loại service - NodePort cho external access
  ports:
  - port: 8000                 # Internal port
    name: http
    nodePort: 30001            # External port (30000-32767)
  selector:
    app: cart
```

**Giải Thích Chi Tiết**:

| Trường | Ý Nghĩa |
|-------|---------|
| `kind: Deployment` | Định nghĩa cách pods chạy (replica, rolling update, ...) |
| `replicas: 1` | Số lượng pod instances chạy cùng lúc |
| `image: changeme/yas-cart:latest` | Docker image URI - **PHẢI thay "changeme" bằng Docker Hub username** |
| `imagePullPolicy: Always` | Luôn pull image mới nhất (dù số version không đổi) |
| `containerPort: 8000` | Port mà ứng dụng lắng nghe bên trong container |
| `SPRING_PROFILES_ACTIVE: kube` | Spring profile để load K8s config |
| `resources.requests` | Resource tối thiểu: nếu không đủ, pod sẽ pending |
| `resources.limits` | Resource tối đa: nếu vượt, pod sẽ killed (OOMKilled) |
| `nodePort: 30001` | Port expose ra host machine (NodePort) |

**Quy Tắc Port Allocation**:
- Java services: 30001-30015, 30020
- BFF services: 30016-30017
- Frontend: 30018-30019

**Cách Cập Nhật Image**:

```bash
# Cách 1: Edit file YAML
sed -i 's/changeme/myusername/g' k8s/deploy/yas-apps/yas-deployment.yaml

# Cách 2: Deploy & cập nhật sau
kubectl set image deployment/cart cart=myusername/yas-cart:latest -n yas-dev
```

---

### 2. File: `k8s/deploy/yas-apps/deploy.sh`

**Mục Đích**: Script bash tự động hóa deployment process

**File Content**:

```bash
#!/bin/bash

# Script này:
# 1. Kiểm tra kubectl connectivity
# 2. Tạo namespace
# 3. Deploy manifests
# 4. Chờ pods ready
# 5. In ra thông tin services

NAMESPACE="${1:-yas-dev}"        # Tham số 1: namespace (mặc định: yas-dev)
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

# Kiểm tra kubectl
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not installed"
    exit 1
fi

# Kiểm tra kubeconfig
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "kubeconfig not found"
    exit 1
fi

# Tạo namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# Deploy
kubectl apply -f yas-deployment.yaml -n "$NAMESPACE"

# Chờ deployments ready
kubectl wait --for=condition=available --timeout=300s deployment --all -n "$NAMESPACE"

# In status
kubectl get deployments -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"
```

**Cách Chạy**:

```bash
# Chạy với namespace mặc định (yas-dev)
cd k8s/deploy/yas-apps
chmod +x deploy.sh
./deploy.sh

# Chạy với namespace custom
./deploy.sh my-namespace

# Hoặc deploy manual:
kubectl apply -f yas-deployment.yaml -n yas-dev
```

**Thanh Tra Scripts**:

```bash
# Xem gì inside script
cat k8s/deploy/yas-apps/deploy.sh

# Chạy với debug mode
bash -x k8s/deploy/yas-apps/deploy.sh

# Chạy từng câu lệnh riêng
kubectl create namespace yas-dev
kubectl apply -f yas-deployment.yaml -n yas-dev
kubectl get pods -n yas-dev
```

---

### 3. File: `.github/workflows/developer-build-cd.yaml`

**Mục Đích**: GitHub Actions workflow để developer manually deploy với selective branches

**Cấu Trúc**:

```yaml
name: Developer Build CD

on:
  workflow_dispatch:              # Manual trigger (GitHub UI)
    inputs:
      cart_branch:                # Input parameter 1
        description: 'Branch for cart service'
        required: false
        default: 'main'
      tax_branch:                 # Input parameter 2
        description: 'Branch for tax service'
        required: false
        default: 'main'
      # ... (20 total service branches)
      namespace:                  # Input parameter 21
        description: 'K8s namespace'
        required: false
        default: 'yas-dev'

jobs:
  get-commit-ids:                 # Job 1: Resolve commit IDs
    runs-on: ubuntu-latest
    outputs:
      cart_tag: ${{ steps.cart.outputs.tag }}    # Output tag cho cart
      tax_tag: ${{ steps.tax.outputs.tag }}      # Output tag cho tax
      # ... (20 total tags)
    steps:
      - name: Get commit IDs
        # Logic: nếu branch=main → tag=latest
        #        nếu branch≠main → tag={commit_id}

  deploy:                         # Job 2: Deploy to K8s
    needs: get-commit-ids
    runs-on: ubuntu-latest
    steps:
      - name: Setup kubeconfig
        # Base64-decode KUBECONFIG secret từ GitHub secrets
      
      - name: Create namespace
        # kubectl create namespace yas-dev
      
      - name: Deploy services
        # kubectl set image deployment/cart cart=registry/image:tag
        # ... (20 total deployments)
      
      - name: Get service info
        # Append service info to GitHub step summary
```

**Luồng Execution**:

1. Developer trigger workflow via GitHub Actions UI
2. Nhập branch names (e.g., `tax_branch=dev_tax_service`)
3. Workflow tính toán commit IDs:
   - Nếu `branch=main` → `tag=latest`
   - Nếu `branch≠main` → `tag={commit_id}`
4. Workflow deploy K8s:
   ```bash
   kubectl set image deployment/cart cart=yourusername/yas-cart:latest
   kubectl set image deployment/tax tax=yourusername/yas-tax:a1b2c3d
   ```
5. Display endpoints trong step summary

---

### 4. File: `.github/workflows/cleanup-deployment.yaml`

**Mục Đích**: GitHub Actions workflow để xóa deployment

```yaml
name: Cleanup Developer Deployment

on:
  workflow_dispatch:
    inputs:
      namespace:
        description: 'K8s namespace to delete'
        required: false
        default: 'yas-dev'
      confirm_delete:
        description: 'Type "DELETE" to confirm'
        required: true

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Verify confirmation
        # Check if input == "DELETE"
        # If not, exit with error
      
      - name: Setup kubeconfig
        # Decode KUBECONFIG secret
      
      - name: Delete namespace
        # kubectl delete namespace yas-dev
        # Tất cả resources bên trong sẽ bị xóa
```

**Lưu Ý**: Phải confirm bằng cách nhập `DELETE` - tránh xóa vô tình

---

## Hướng Dẫn Triển Khai Từng Bước

### Phase 1: Chuẩn Bị (1 giờ)

**Step 1.1: Cài đặt công cụ cần thiết**

```bash
# macOS
brew install kubectl minikube docker

# Linux (Ubuntu)
sudo apt-get update
sudo apt-get install -y docker.io
curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Cài minikube
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
chmod +x minikube && sudo mv minikube /usr/local/bin/
```

**Step 1.2: Tạo Docker Hub account & token**

```
1. Vào https://hub.docker.com/signup
2. Tạo account mới
3. Tạo Personal Access Token:
   https://hub.docker.com/settings/security
   → New Access Token
   → Copy token (lưu vào somewhere safe)
```

**Step 1.3: Setup GitHub Secrets**

```
GitHub Repo → Settings → Secrets and variables → Actions
→ New repository secret (3 times):
  1. DOCKER_HUB_USERNAME = your_username
  2. DOCKER_HUB_PASSWORD = your_token
  3. KUBECONFIG = base64(~/.kube/config)
```

---

### Phase 2: Khởi Động Kubernetes ⭐ **CHOOSE ONE**

#### **Option A: 3 Ubuntu Server VMs (Recommended for Production Testing)**

**Thời gian: 45 phút**

Quay lại **"Cấu Hình Kubernetes Cluster → Tùy Chọn 1"** và hoàn thành:
- Phase 0: Setup all 3 VMs (Docker, network, k8s tools) - 30 phút
- Phase 1: Master node initialization - 10 phút
- Phase 2: Worker nodes join cluster - 5 phút
- Phase 3: Copy kubeconfig to dev machine - đã có

Sau khi hoàn thành, kiểm tra:

```bash
# Trên dev machine:
kubectl get nodes
# OUTPUT:
# NAME             STATUS   ROLES           AGE
# master           Ready    control-plane   10m
# worker1          Ready    <none>          5m
# worker2          Ready    <none>          5m

kubectl get pods --all-namespaces
# kiểm tra tất cả pods running (calico, coredns, etc.)
```

**Tiếp tục với Phase 3**

#### **Option B: Minikube (Local Development)**

**Thời gian: 15 phút**

**Step 2.1: Khởi động Minikube**

```bash
minikube start \
  --memory=16g \
  --disk-size=40gb \
  --cpus=4

# Chờ tới khi tất cả components ready (~3 phút)
minikube status

# Verify kết nối
kubectl cluster-info
kubectl get nodes     # Output: 1 node (minikube)
```

**Step 2.2: Cấu hình Network**

```bash
# Lấy Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Thêm vào /etc/hosts
echo "$MINIKUBE_IP yas.local" | sudo tee -a /etc/hosts
echo "$MINIKUBE_IP api.yas.local" | sudo tee -a /etc/hosts

# Verify
ping yas.local
```

**Step 2.3: Verify kubectl access**

```bash
kubectl version
kubectl get nodes
kubectl get ns          # Liệt kê namespaces

# Output mong đợi:
# NAME              STATUS   ROLES           AGE
# minikube          Ready    control-plane   5m
```

**Tiếp tục với Phase 3**

---

### Phase 3: Chuẩn Bị Infrastructure Services (1 giờ)

**Step 3.1: Deploy PostgreSQL**

```bash
# Nếu project đã có setup script:
cd k8s/deploy
./setup-cluster.sh

# Hoặc manual:
kubectl create namespace postgres
# Deploy PostgreSQL (using Helm or manifest)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql -n postgres
```

**Step 3.2: Deploy Kafka, Elasticsearch, Redis (tuỳ chọn)**

```bash
# Chỉ deploy nếu applications cần
kubectl create namespace kafka
kubectl create namespace elasticsearch

# Setup script sẽ handle:
./setup-keycloak.sh
./setup-redis.sh
```

**Step 3.3: Verify infrastructure**

```bash
kubectl get pods -n postgres
kubectl get pods -n kafka
kubectl get svc -n postgres
```

---

### Phase 4: Deploy YAS Applications (30 phút)

**Step 4.1: Cập nhật Image Username**

```bash
cd k8s/deploy/yas-apps

# Thay "changeme" bằng Docker Hub username
sed -i 's|changeme/|yourusername/|g' yas-deployment.yaml

# Verify
grep "image:" yas-deployment.yaml | head -5
# Output:
# image: yourusername/yas-cart:latest
# image: yourusername/yas-customer:latest
```

**Step 4.2: Deploy Applications**

```bash
# Cách 1: Dùng script
chmod +x deploy.sh
./deploy.sh

# Cách 2: Manual
kubectl apply -f yas-deployment.yaml -n yas-dev

# Chờ pods ready
kubectl get pods -n yas-dev -w

# Expected output (sau ~5 phút):
# NAME                         READY   STATUS    RESTARTS
# cart-5d4f9c8b8f-xyz         1/1     Running   0
# customer-5d4f9c8b8f-abc     1/1     Running   0
# ... (18 more)
```

**Step 4.3: Verify Deployments**

```bash
# Kiểm tra deployments
kubectl get deployments -n yas-dev
# Output: 20 deployments, 20 ready

# Kiểm tra services
kubectl get svc -n yas-dev
# Output: 20 services with NodePort assigned (30001-30020)

# Kiểm tra pods
kubectl get pods -n yas-dev
# Output: 20 pods running

# Kiểm tra logs
kubectl logs -n yas-dev deployment/cart
kubectl logs -n yas-dev pod/cart-xyz -f
```

---

### Phase 5: Kiểm Thử Access (15 phút)

#### **Option A: 3 Ubuntu Server VMs Cluster**

**Step 5.1: Lấy IPs của Worker nodes**

```bash
# Trên dev machine:
# Services được expose via NodePort trên tất cả nodes
# Có thể access qua bất kỳ node nào

# Worker 1 IP: 192.168.1.11
# Worker 2 IP: 192.168.1.12

# Test API endpoints
curl http://192.168.1.11:30001/actuator/health        # Cart (via Worker1)
curl http://192.168.1.12:30002/actuator/health        # Customer (via Worker2)
curl http://192.168.1.11:30014/actuator/health        # Tax

# Expected response:
# {"status":"UP","components":{...}}

# Hoặc dùng hostname (nếu setup /etc/hosts):
curl http://k8s-worker1:30001/actuator/health
curl http://k8s-worker2:30002/actuator/health
```

**Step 5.2: Thử access frontends**

```bash
# Storefront
curl http://192.168.1.11:30018
# Expected: HTML response (Next.js app)

# Backoffice
curl http://192.168.1.12:30019
```

**Step 5.3: Thử từ browser**

```
Mở browser:
- Storefront: http://192.168.1.11:30018  (hoặc http://k8s-worker1:30018)
- Backoffice: http://192.168.1.12:30019  (hoặc http://k8s-worker2:30019)
- Cart API: http://192.168.1.11:30001
```

#### **Option B: Minikube**

**Step 5.1: Thử access services**

```bash
# Lấy Minikube IP
MINIKUBE_IP=$(minikube ip)

# Test API endpoints
curl http://$MINIKUBE_IP:30001/actuator/health        # Cart
curl http://$MINIKUBE_IP:30002/actuator/health        # Customer
curl http://$MINIKUBE_IP:30014/actuator/health        # Tax

# Expected response:
# {"status":"UP","components":{...}}

# Thử qua hostname
curl http://yas.local:30001/actuator/health
```

**Step 5.2: Thử access frontends**

```bash
# Storefront
curl http://$MINIKUBE_IP:30018
# Expected: HTML response (Next.js app)

# Backoffice
curl http://$MINIKUBE_IP:30019
```

**Step 5.3: Thử từ browser**

```
Mở browser:
- Storefront: http://yas.local:30018
- Backoffice: http://yas.local:30019
- Cart API: http://yas.local:30001
```

---

## Luồng Hoạt Động Chi Tiết

### Scenario: Developer Test Tax Service Feature

**Timeline**:
```
Day 1:
  10:00 - Developer tạo branch dev_tax_service
  10:05 - Làm việc, commit code
  10:30 - git push origin dev_tax_service
           → CI workflow auto trigger
           → Tests pass
           → Build image: yourusername/yas-tax:a1b2c3d
           → Push to Docker Hub
  11:00 - Docker Hub có image sẵn

Day 1 (continued):
  14:00 - Developer Ready to test
  14:05 - GitHub Actions → Developer Build CD
  14:06 - Input:
          - tax_branch: dev_tax_service
          - cart_branch: main
          - ... (others: main)
  14:07 - Run workflow
          → Resolve tags:
            - tax_tag: a1b2c3d
            - others: latest
          → Deploy K8s
          → Pods restart
  14:15 - Deployment complete
          → Open browser
          → curl http://api.yas.local:30014/health (Minikube)
          →     or http://192.168.1.11:30014/health (3-VM)
          → Test tax-related features
  
Day 2:
  09:00 - After testing, all OK
  09:05 - GitHub Actions → Cleanup Developer Deployment
  09:06 - Confirm: DELETE
  09:07 - Namespace deleted, cleanup complete
```

### Detailed Workflow Diagram

**CI Workflow** (Automatic):
```
Developer commit
      ↓
GitHub detected push to dev_tax_service
      ↓
Trigger: tax-ci.yaml workflow
      ↓
┌─────────────────────────┐
│ Testing Job             │
├─────────────────────────┤
│ 1. mvn clean install    │
│ 2. Run unit tests       │
│ 3. SonarCloud scan      │
│ 4. Snyk security scan   │
└─────────────────────────┘
      ↓
All pass? → Trigger: build job
      ↓
┌─────────────────────────┐
│ Build Job               │
├─────────────────────────┤
│ 1. mvn clean package    │
│ 2. Get commit ID: a1b2c │
│ 3. docker build         │
│ 4. docker login (Hub)   │
│ 5. docker push          │
└─────────────────────────┘
      ↓
Image in Docker Hub:
  yourusername/yas-tax:a1b2c3d
  yourusername/yas-tax:latest (if main)
```

**CD Workflow** (Manual):
```
Developer trigger: Developer Build CD workflow
      ↓
Inputs:
  tax_branch: dev_tax_service
  other_branch: main
      ↓
Get Commit IDs Job:
  tax_branch (dev_tax_service) → resolve commit → a1b2c3d
  other_branch (main) → use → latest
      ↓
Deploy Job:
  1. Setup kubeconfig from secret
  2. Create namespace yas-dev
  3. Update deployments:
     kubectl set image deployment/tax \
       tax=yourusername/yas-tax:a1b2c3d
     kubectl set image deployment/cart \
       cart=yourusername/yas-cart:latest
  4. Wait for rollout
  5. Get services & endpoints
      ↓
Output: Service endpoints
  Cart: :30001
  Tax: :30014 ← Your featured service
  ...
```

---

## Chạy & Kiểm Thử CI/CD

### Test 1: Trigger CI Workflow

**Step 1: Tạo feature branch**

```bash
git checkout -b test-feature
```

**Step 2: Làm thay đổi code**

```bash
echo "// Test change" >> tax/src/main/java/com/example/TaxService.java
git add .
git commit -m "Test CI workflow"
git push origin test-feature
```

**Step 3: Monitor CI workflow**

```
GitHub → Actions → Workflows → tax-ci
→ Xem logs
→ Thường mất 5-10 phút
→ Verify: Đó là test job, build job giành được success status
```

**Step 4: Kiểm tra Docker Hub**

```bash
docker pull yourusername/yas-tax:test-feature-abc1234
# Nếu pull thành công → CI workflow successful!
```

---

### Test 2: Trigger Developer Build CD

**Step 1: Go to GitHub Actions**

```
GitHub → Actions 
→ Developer Build CD
→ Run workflow button
```

**Step 2: Fill parameters**

```
cart_branch: main
tax_branch: test-feature
otros: main (keep default)
namespace: yas-dev-test
```

**Step 3: Run**

```
Click "Run workflow"
→ Xem workflow logs
→ Thường mất 2-5 phút
→ Check "Deploy" job logs
```

**Step 4: Verify K8s deployment**

```bash
kubectl get deployments -n yas-dev-test
kubectl get svc -n yas-dev-test -o wide
kubectl get pods -n yas-dev-test

# Test endpoint
curl $(minikube ip):30014/actuator/health
```

---

### Test 3: Cleanup Workflow

**Step 1: Trigger Cleanup**

```
GitHub → Actions → Cleanup Developer Deployment
→ Run workflow
```

**Step 2: Confirm deletion**

```
Input: DELETE (exactly)
Run workflow
```

**Step 3: Verify**

```bash
kubectl get namespace yas-dev-test 2>/dev/null || echo "✓ Namespace deleted"
```

---

## Troubleshooting

### Issue 1: CI Workflow Fails - Docker Push Error

**Symptoms**:
```
Error: unauthorized: incorrect username password
```

**Nguyên Nhân**:
- Docker Hub credentials sai hoặc hết hạn
- Secret chưa được tạo hoặc sai tên

**Cách Fix**:

```bash
# 1. Verify credentials locally
docker login -u yourusername

# 2. Check GitHub secrets
GitHub → Settings → Secrets and variables → Actions
→ Check DOCKER_HUB_USERNAME & DOCKER_HUB_PASSWORD

# 3. Regenerate token nếu cần
# Hub.docker.com → Settings → Security
# → Delete old token & create new one

# 4. Update secret:
# GitHub → Secrets → DOCKER_HUB_PASSWORD → Edit
# → Paste new token
```

---

### Issue 2: CD Workflow Fails - kubeconfig Error

**Symptoms**:
```
error: unable to read client key /root/.kube/config
```

**Nguyên Nhân**:
- KUBECONFIG secret không base64-encoded đúng
- Secret bị corrupt hoặc expire

**Cách Fix**:

```bash
# 1. Re-generate KUBECONFIG
cat ~/.kube/config | base64 | tr -d '\n'

# 2. Update secret:
GitHub → Settings → Secrets → KUBECONFIG → Edit
→ Paste new base64 content

# 3. Verify kubeconfig locally
cat ~/.kube/config | wc -c  # ~2000 bytes typical
```

---

### Issue 3: Pods Stuck in Pending

**Symptoms**:
```bash
kubectl get pods -n yas-dev
# NAME                        READY   STATUS    RESTARTS
# cart-5d4f9c8b8f-xyz        0/1     Pending   0
```

**Nguyên Nhân**:
- Không đủ resources trên nodes
- Image không được tìm thấy (registry auth issue)
- PVC pending

**Cách Fix**:

```bash
# 1. Check pod events
kubectl describe pod cart-5d4f9c8b8f-xyz -n yas-dev
→ Xem "Events" section

# 2. Check node resources
kubectl top nodes
kubectl describe node minikube
→ Look for "Allocatable" vs "Allocated resources"

# 3. If not enough resources:
# Stop & restart Minikube with more memory
minikube stop
minikube delete
minikube start --memory=20g

# 4. If image pull error:
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=yourusername \
  --docker-password=yourtoken \
  -n yas-dev

# Edit deployment to use secret:
# spec:
#   template:
#     spec:
#       imagePullSecrets:
#       - name: regcred
```

---

### Issue 4: Cannot Access Services via NodePort

**Symptoms**:
```bash
curl http://localhost:30001  # Connection refused
```

**Nguyên Nhân**:
- NodePort service chưa được tạo
- Minikube IP không match
- Firewall blocking

**Cách Fix**:

```bash
# 1. Verify service exists
kubectl get svc cart -n yas-dev -o wide

# 2. Get Minikube IP
MINIKUBE_IP=$(minikube ip)
echo $MINIKUBE_IP

# 3. Try with IP instead of localhost
curl http://$MINIKUBE_IP:30001/actuator/health

# 4. Test pod directly
kubectl port-forward svc/cart 8000:8000 -n yas-dev
→ Open new terminal:
curl http://localhost:8000/actuator/health

# 5. Add to /etc/hosts
echo "$MINIKUBE_IP yas.local" | sudo tee -a /etc/hosts
curl http://yas.local:30001
```

---

### Issue 5: Image Tag Not Resolved Correctly in CD

**Symptoms**:
```
Workflow logs show: "commit_id=unknown"
```

**Nguyên Nhân**:
- Branch chưa được push lên remote
- Typo trong branch name

**Cách Fix**:

```bash
# 1. Verify branch exists on GitHub
git branch -a
git push origin dev_tax_service

# 2. Wait 30 seconds for GitHub sync

# 3. Re-run Developer Build CD workflow

# 4. Check workflow logs:
GitHub → Actions → Developer Build CD → Latest run
→ Check "get-commit-ids" step
→ See actual commit ID resolved
```

---

### Issue 6: (3-VM Cluster) Workers Cannot Join - Network Issue

**Symptoms**:
```bash
# Trên Worker node khi chạy kubeadm join:
error execution phase preflight: [preflight] Some fatal errors occurred:
    [ERROR] PERM_DENIED: could not connect to the server
```

**Nguyên Nhân**:
- Master-Worker network không kết nối được
- Firewall chặn port 6443 (API server)
- kubeadm join command token hết hạn

**Cách Fix**:

```bash
# 1. Kiểm tra network connectivity
ssh ubuntu@192.168.1.11    # Worker 1
ping 192.168.1.10           # Ping Master - phải thành công

# 2. Kiểm tra firewall trên Master
ssh ubuntu@192.168.1.10
sudo ufw allow 6443/tcp
sudo ufw allow 10250/tcp

# 3. Nếu token hết hạn (>24h), generate token mới:
# Trên Master:
kubeadm token create --print-join-command

# Copy new command & run trên Worker node
sudo kubeadm join 192.168.1.10:6443 \
  --token NEWTOKENHERE \
  --discovery-token-ca-cert-hash sha256:NEWHASHHERE
```

---

### Issue 7: (3-VM Cluster) Calico Pods Crash with Init Error

**Symptoms**:
```bash
kubectl get pods -n calico-system
# calico-node-xyz:   0/1     Init:0/1

kubectl logs -n calico-system pod/calico-node-xyz --previous
# Error: ...kernel version not supported...
```

**Nguyên Nhân**:
- Ubuntu kernel version quá cũ
- Calico version không compatible

**Cách Fix**:

```bash
# 1. Upgrade kernel trên tất cả nodes:
ssh ubuntu@192.168.1.10    # Master
sudo apt-get update
sudo apt-get install -y linux-image-generic
sudo reboot

# Repeat cho Worker nodes

# 2. Check kernel version (phải >= 3.10):
uname -r    # Output: 5.15.0-xx hoặc cao hơn là OK

# 3. Verify Calico status:
kubectl get pods -n calico-system
# Tất cả pods phải Running
```

---

### Issue 8: (3-VM Cluster) Cannot Access NodePort from Outside Network

**Symptoms**:
```bash
# Từ dev machine:
curl http://192.168.1.11:30001/actuator/health
# Connection refused
```

**Nguyên Nhân**:
- Worker node firewall chặn
- iptables rules không setup đúng
- kube-proxy không running

**Cách Fix**:

```bash
# 1. Kiểm tra service tồn tại:
kubectl get svc cart -n yas-dev -o wide
# OUTPUT: services cần show NodePort

# 2. Kiểm tra kube-proxy status:
kubectl get ds -n kube-system
# kube-proxy phải running trên tất cả nodes

# 3. Mở firewall trên Worker nodes:
ssh ubuntu@192.168.1.11    # Worker 1
sudo ufw allow 30000:32767/tcp
sudo systemctl reload ufw

# Repeat cho Worker 2

# 4. Test từ dev machine:
curl -v http://192.168.1.11:30001/actuator/health
# -v để xem chi tiết requests
```

---

### Issue 9: (3-VM Cluster) Master Node Recovery After Crash

**Symptoms**:
```bash
kubectl cluster-info
# Unable to connect to server
```

**Nguyên Nhân**:
- Control plane pods crashed
- Master node crashed

**Cách Fix**:

```bash
# 1. SSH vào Master node:
ssh ubuntu@192.168.1.10

# 2. Check kubelet status:
sudo systemctl status kubelet
# Phải là "active (running)"

# 3. Restart kubelet:
sudo systemctl restart kubelet

# 4. Check control plane pods:
sudo kubectl get pods -n kube-system --kubeconfig=/etc/kubernetes/admin.conf

# 5. Restart control plane (nguy hiểm, chỉ làm nếu cần):
sudo systemctl restart kubelet
# Nach 30 seconds, pods sẽ restart automatically

# 6. Verify recovery (từ dev machine):
kubectl cluster-info
kubectl get nodes
# Master phải back to "Ready"
```

---

### Issue 10: (3-VM Cluster) etcd Database Corrupted

**Symptoms**:
```bash
# Control plane pods continuously crashing, restarting
kubectl get pods -n kube-system
# etcd-master:  0/1     CrashLoopBackOff
```

**Nguyên Nhân**:
- Hard shutdown không graceful
- Disk space penuh
- etcd corruption

**Cách Fix** (Nuclear Option - Restart từ scratch):

```bash
# BACKUP first (trên Master):
ssh ubuntu@192.168.1.10
sudo cp -r /etc/kubernetes /etc/kubernetes-backup
sudo cp -r /var/lib/etcd /var/lib/etcd-backup

# Nếu etcd hoàn toàn corrupt, phải reset cluster:
# 1. Trên Master:
sudo kubeadm reset
sudo rm -rf /etc/kubernetes /var/lib/etcd

# 2. Re-initialize:
sudo kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --pod-network-cidr=10.244.0.0/16

# 3. Trên Workers:
sudo kubeadm reset
# Sau đó re-join cluster

# ⚠️  Cảnh báo: Pro cedure này sẽ xóa tất cả deployments!
```

---

## Cheat Sheet - Lệnh Thường Dùng

```bash
# ========== 3-VM Cluster ==========
# SSH đến các nodes:
ssh -i ~/.ssh/yas-vm ubuntu@192.168.1.10      # Master
ssh -i ~/.ssh/yas-vm ubuntu@192.168.1.11      # Worker 1
ssh -i ~/.ssh/yas-vm ubuntu@192.168.1.12      # Worker 2

# Check cluster status:
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl top nodes

# SSH vào node and check resources:
ssh ubuntu@k8s-master
free -h
df -h
ps aux | grep kube

# kubeadm commands:
kubeadm token list
kubeadm token create --ttl 2h
kubeadm reset
kubeadm upgrade plan/apply

# Systemctl (trên node):
sudo systemctl restart kubelet
sudo systemctl restart docker
sudo journalctl -u kubelet -n 50 -f

# ========== Minikube ==========
# Minikube
minikube start --memory=16g --disk-size=40gb
minikube stop
minikube delete
minikube ip
minikube ssh

# ========== kubectl - Common ==========
kubectl create ns yas-dev
kubectl delete ns yas-dev
kubectl get ns

# kubectl - Deployments
kubectl get deployments -n yas-dev
kubectl describe deployment cart -n yas-dev
kubectl set image deployment/cart cart=newimage:tag -n yas-dev

# kubectl - Services
kubectl get svc -n yas-dev -o wide
kubectl describe svc cart -n yas-dev

# kubectl - Pods
kubectl get pods -n yas-dev
kubectl describe pod cart-xyz -n yas-dev
kubectl logs -n yas-dev deployment/cart
kubectl logs -n yas-dev pod/cart-xyz -f
kubectl exec -n yas-dev pod/cart-xyz -- /bin/sh

# kubectl - Debug
kubectl top nodes
kubectl top pods -n yas-dev
kubectl get events -n yas-dev --sort-by='.lastTimestamp'
kubectl port-forward svc/cart 8000:8000 -n yas-dev

# Docker
docker login -u yourusername
docker tag yas-tax yourusername/yas-tax:latest
docker push yourusername/yas-tax:latest
docker pull yourusername/yas-tax:latest

# GitHub CLI
gh secret list               # List all secrets
gh secret set VAR_NAME < value.txt
gh run list                  # List workflow runs
gh run view {run_id} --log   # View run logs
```

---

## Summary

| Giai Đoạn | 3-VM Cluster | Minikube | Trạng Thái |
|----------|--------|--------|-----------|
| **Setup** | GitHub, Docker Hub, 3 VMs | GitHub, Docker Hub | 1-1.5 giờ |
| **Kubernetes** | kubeadm (Master + 2 Workers) | Minikube start | 45 phút / 15 phút |
| **Network Setup** | SSH, kubeconfig copy | Minikube tunnel | 15 phút / 5 phút |
| **Deploy Services** | kubectl apply | kubectl apply | 30 phút |
| **Development** | Git + GitHub | Git + GitHub | Per feature |
| **Testing** | Developer Build CD | Developer Build CD | 5 phút |
| **Cleanup** | Cleanup Workflow | Cleanup Workflow | 2 phút |
| **Resources** | 8GB×3 VMs + 192.168.1.x network | 16GB local machine | One-time |
| **Production Ready** | ✅ YES | ⚠️ Local only |
| **Persistence** | ✅ Data survives reboots | ⚠️ Local storage only |
| **Scalability** | ✅ Easy to add 3rd+ nodes | ❌ Limited to 1 node |

**Recommended**: Use 3-VM cluster cho development team collaboration. Use Minikube cho local solo testing.

---

## Tài Liệu Tham Khảo

- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [Minikube Handbook](https://minikube.sigs.k8s.io/)
- [Docker Hub Docs](https://docs.docker.com/docker-hub/)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Spring Boot K8s Guide](https://spring.io/guides/kubernetes/deploying-spring-boot-app-to-kubernetes)

---

**Last Updated**: April 6, 2026  
**Version**: 1.0  
**Status**: Ready for Production
