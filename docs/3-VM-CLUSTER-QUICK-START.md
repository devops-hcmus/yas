# YAS K8s - 3 Ubuntu Server VMs Setup Quick Start

**Thời gian**: ~1.5 giờ để setup cluster hoàn chỉnh

**Cấu hình**: 
- **Master**: 192.168.1.10 (8GB RAM, 4 CPU, 50GB Disk)
- **Worker 1**: 192.168.1.11 (8GB RAM, 4 CPU, 50GB Disk)
- **Worker 2**: 192.168.1.12 (8GB RAM, 4 CPU, 50GB Disk)
- OS: Ubuntu 24 LTS
- Network: 192.168.1.x (LAN local)

---

## 🚀 Quick Start (Copy-Paste Commands)

### Phase 1: Chuẩn Bị (Trên tất cả 3 VMs)

```bash
# SSH vào Master
ssh ubuntu@192.168.1.10

# ===== CÓP TOÀN BỘ SCRIPT NÀY & PASTE VÀO TERMINAL =====
# (Nhấp chuột phải → Paste)

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Cài Docker
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker

# Network config
sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Cài Kubernetes tools
curl -fsSLo /tmp/golang.key https://dl.google.com/linux/linux_signing_key.pub
sudo apt-key add /tmp/golang.key
sudo apt-get install -y apt-transport-https ca-certificates

echo "deb https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubeadm=1.28.* kubelet=1.28.* kubectl=1.28.*
sudo apt-mark hold kubeadm kubelet kubectl

# Verify
docker --version
kubeadm version
echo "✅ Master node ready!"
```

👆 **REPEAT trên Worker 1 & Worker 2** (SSH đến 192.168.1.11 & 192.168.1.12)

---

### Phase 2: Master Node Initialization

```bash
# Trên Master (192.168.1.10)
ssh ubuntu@192.168.1.10

# Initialize cluster
sudo kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --pod-network-cidr=10.244.0.0/16

# Setup kubeconfig
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Verify
kubectl cluster-info
kubectl get nodes
# Output: Master sẽ ở "NotReady" (chờ networking)

echo "✅ Master initialized!"
```

---

### Phase 3: Install Calico Networking

```bash
# Trên Master (192.168.1.10)
ssh ubuntu@192.168.1.10

# Install Tigera Operator
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml

# Chờ operators ready
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
      cidr: 10.244.0.0/16
      encapsulation: VXLan
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Chờ Calico ready (~2 phút)
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s

# Verify
kubectl get nodes
# Output: Master phải ở "Ready"

echo "✅ Calico installed!"
```

---

### Phase 4: Generate Worker Join Command

```bash
# Trên Master (192.168.1.10)
ssh ubuntu@192.168.1.10

# Generate join command
echo "===== COPY COMMAND BELOW ====="
kubeadm token create --print-join-command
echo "===== END COPY ====="

# Output ví dụ:
# kubeadm join 192.168.1.10:6443 \
#   --token 7ab2c8.1c5de5e8b3e2f5a6 \
#   --discovery-token-ca-cert-hash sha256:abc123...
```

---

### Phase 5: Workers Join Cluster

```bash
# SSH vào Worker 1 (192.168.1.11)
ssh ubuntu@192.168.1.11

# Paste join command từ Phase 4:
sudo kubeadm join 192.168.1.10:6443 \
  --token 7ab2c8.1c5de5e8b3e2f5a6 \
  --discovery-token-ca-cert-hash sha256:abc123...

# Output: "This node has joined the cluster."
echo "✅ Worker 1 joined!"
```

```bash
# SSH vào Worker 2 (192.168.1.12)
ssh ubuntu@192.168.1.12

# Paste tương tự:
sudo kubeadm join 192.168.1.10:6443 \
  --token 7ab2c8.1c5de5e8b3e2f5a6 \
  --discovery-token-ca-cert-hash sha256:abc123...

echo "✅ Worker 2 joined!"
```

---

### Phase 6: Verify Cluster

```bash
# Trên Master (192.168.1.10)
ssh ubuntu@192.168.1.10

# Check all nodes
kubectl get nodes
# Expected output:
# NAME     STATUS   ROLES           AGE
# master   Ready    control-plane   5m
# worker1  Ready    <none>          2m
# worker2  Ready    <none>          1m

# Check all pods
kubectl get pods --all-namespaces

# Get kubeconfig for dev machine
cat ~/.kube/config

echo "✅ Cluster ready!"
```

---

### Phase 7: Setup kubeconfig on Dev Machine

```bash
# Trên dev machine (máy local của bạn)

# 1. Create ~/.kube directory
mkdir -p ~/.kube

# 2. Copy Master kubeconfig
# SSH vào Master & copy:
# cat ~/.kube/config

# 3. Paste vào dev machine:
cat > ~/.kube/config <<'EOF'
# PASTE kubeconfig content FROM MASTER HERE
EOF

# 4. Verify connection
kubectl cluster-info
kubectl get nodes
# Should show: 1 master + 2 workers

# 5. Setup GitHub Secret (Base64-encoded)
cat ~/.kube/config | base64 | tr -d '\n'
# Copy output → GitHub Secrets → KUBECONFIG

echo "✅ Dev machine ready!"
```

---

## 📋 Deploy YAS Services

```bash
# Trên dev machine

# 1. Clone repo (if not already)
# cd /path/to/yas-project2

# 2. Update image username
cd k8s/deploy/yas-apps
sed -i 's|changeme|yourusername|g' yas-deployment.yaml

# 3. Deploy
kubectl apply -f yas-deployment.yaml -n yas-dev

# 4. Wait for pods
kubectl get pods -n yas-dev -w

# 5. Verify services
kubectl get svc -n yas-dev
# All 20 services should show NodePort

# 6. Test access
curl http://192.168.1.11:30001/actuator/health
curl http://192.168.1.12:30018

echo "✅ YAS services deployed!"
```

---

## 🔧 Troubleshooting Quick Links

| Problem | Solution |
|---------|----------|
| Workers não join | Check firewall: `sudo ufw allow 6443/tcp 10250/tcp` |
| Calico stuck | `kubectl describe pod` → check kernel version (`uname -r`) |
| Cannot access NodePort | `sudo ufw allow 30000:32767/tcp` on workers |
| Master crashed | `sudo systemctl restart kubelet` on master |
| CD workflow fails | Re-generate kubeconfig → update GitHub secret |

👉 **Full troubleshooting**: See [SETUP_AND_DEPLOYMENT_GUIDE.md](./SETUP_AND_DEPLOYMENT_GUIDE.md#troubleshooting)

---

## 📚 Next Steps

1. **Deploy YAS Services** (see "Deploy YAS Services" above)
2. **Test CI/CD**:
   - Push code to GitHub
   - Manual trigger: GitHub Actions → Developer Build CD
   - Check services accessible via NodePort
3. **Cleanup**: Trigger cleanup workflow when done testing

---

## 🗺️ Network Map

```
┌─────────────────────────────────────────────────────────────┐
│                   192.168.1.x LAN                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Master (192.168.1.10)                              │   │
│  │  - 8GB RAM, 4 CPU, 50GB Disk                        │   │
│  │  - Control Plane, etcd, API Server                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│         ┌────────────────┼────────────────┐                │
│         │                │                │                │
│  ┌─────────────────┐  ┌────────────────┐  ┌─────────────────────┐
│  │ Worker 1        │  │ Worker 2       │  │ Dev Machine         │
│  │ 192.168.1.11    │  │ 192.168.1.12   │  │ (your laptop)       │
│  │ 8GB, 4CPU       │  │ 8GB, 4CPU      │  │                     │
│  │                 │  │                │  │ kubectl access      │
│  │ NodePort:       │  │ NodePort:      │  │ via kubeconfig      │
│  │ 30001-30020     │  │ 30001-30020    │  │                     │
│  └─────────────────┘  └────────────────┘  └─────────────────────┘
│                                                              │
└─────────────────────────────────────────────────────────────┘

Access patterns:
- curl http://192.168.1.11:30001/actuator/health
- curl http://192.168.1.12:30018
- kubectl commands from Dev Machine (anywhere on LAN)
```

---

## ✅ Verification Checklist

- [ ] 3 VMs created & accessible via SSH
- [ ] Phase 1-2: Docker, kubeadm, kubelet installed on all VMs
- [ ] Master node initialized
- [ ] Calico networking installed
- [ ] Worker nodes joined cluster
- [ ] `kubectl get nodes` show 3 Ready nodes
- [ ] Dev machine can run `kubectl` commands
- [ ] GitHub KUBECONFIG secret created
- [ ] YAS services deployed
- [ ] Services accessible via NodePort (30001-30020)

---

## 📞 Common Commands

```bash
# Monitor cluster
kubectl get nodes -w
kubectl top nodes
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Debug
kubectl describe pod POD_NAME -n yas-dev
kubectl logs deployment/cart -n yas-dev -f
kubectl exec -it pod/PODNAME -n yas-dev -- /bin/bash

# SSH vào nodes từ dev machine
ssh ubuntu@192.168.1.10    # Master
ssh ubuntu@192.168.1.11    # Worker 1
ssh ubuntu@192.168.1.12    # Worker 2

# Systemctl on nodes
ssh ubuntu@192.168.1.10 'sudo systemctl restart kubelet'
ssh ubuntu@192.168.1.10 'sudo journalctl -u kubelet -n 50 -f'
```

---

**Last Updated**: April 6, 2026  
**Duration**: ~1.5 hours for complete setup  
**Status**: Production-ready 3-node K8s cluster
