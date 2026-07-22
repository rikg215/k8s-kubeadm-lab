#!/usr/bin/env bash
# rebuild.sh — Proxmox-level kubeadm cluster orchestrator
# Runs ON the Proxmox host (pve-01). Clones VMs from cloud-init template, builds cluster.
#   Template 9997 = Debian 13 + cloud-init + qemu-guest-agent (built from 9003)
#   CNI = Flannel (mirrors KodeKloud CKA course)
#   SSH  = labuser@<ip> with sudo (cloud-init injects your pubkey)
set -euo pipefail

# ═══════════════════════════════════════════════════════════
# STEP 1: Clone VMs from cloud-init template
# ═══════════════════════════════════════════════════════════
source ./config.sh

clone_vm() {
    local vmid=$1 hostname=$2 ip=$3

    # IDEMPOTENCY GUARD: skip if VM already exists
    if qm status "$vmid" &>/dev/null; then
        echo "==> VM $vmid ($hostname) already exists, skipping clone"
        # Still ensure it's running
        qm start "$vmid" 2>/dev/null || true
        return 0
    fi

    echo "==> Full-cloning template $TEMPLATE_ID → VM $vmid ($hostname)"
    qm clone "$TEMPLATE_ID" "$vmid" --name "$hostname" --full
    qm set "$vmid" --ipconfig0 "ip=$ip,gw=$GATEWAY"
    qm set "$vmid" --sshkey "$SSH_KEY"
    qm set "$vmid" --ciuser "$SSH_USER"
    qm start "$vmid"
}

# Clone control plane
clone_vm "$CP_VMID" "$CP_HOSTNAME" "$CP_IP"

# Clone workers in a loop
for ((i=0; i<WORKER_COUNT; i++)); do
    worker_vmid=$((WORKER_START_VMID + i))
    worker_ip_num=$((WORKER_START_IP + i))
    worker_hostname="${WORKER_PREFIX}$((i+1))"
    worker_ip="192.168.0.${worker_ip_num}/24"
    clone_vm "$worker_vmid" "$worker_hostname" "$worker_ip"
done

# ═══════════════════════════════════════════════════════════
# STEP 2: Wait for all VMs to boot (cloud-init finishes, SSH up)
# ═══════════════════════════════════════════════════════════
wait_for_ssh() {
    local ip=$1 hostname=$2
    local max_attempts=60 attempt=0
    echo "==> Waiting for cloud-init + SSH on $hostname ($ip)..."
    # cloud-init runs on first boot — give it time
    until ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" 'echo ready' &>/dev/null; do
        ((++attempt))
        if ((attempt >= max_attempts)); then
            echo "ERROR: $hostname ($ip) not reachable after $((max_attempts * 5))s" >&2
            echo "       Check: qm status <vmid> / console for cloud-init errors" >&2
            exit 1
        fi
        sleep 5
    done
    echo "==> $hostname is up ($((attempt * 5))s)"
}

# ═══════════════════════════════════════════════════════════
# STEP 3: Node-level setup (SSH + sudo on each VM)
# ═══════════════════════════════════════════════════════════
setup_node() {
    local ip=$1 hostname=$2

    echo "==> Setting up $hostname ($ip)"

    # IDEMPOTENCY GUARD: skip if kubeadm already installed
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" 'command -v kubeadm &>/dev/null && echo installed' | grep -q installed; then
        echo "    kubeadm already installed, skipping node setup"
        return 0
    fi

    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" bash <<'ENDSSH'
set -euo pipefail

# === containerd (Debian) ===
# Docker's apt repo for containerd
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y containerd.io

# Enable SystemdCgroup (CKA requirement)
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# === kubeadm/kubelet/kubectl (v1.36, Debian) ===
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt update
sudo apt install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl

# Enable kubelet (it'll fail-loop until kubeadm init — that's normal)
sudo systemctl enable kubelet
ENDSSH
}

# ═══════════════════════════════════════════════════════════
# STEP 4: kubeadm init on control plane
# ═══════════════════════════════════════════════════════════
init_control_plane() {
    local ip=$1

    # GUARD
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" '[ -f /etc/kubernetes/admin.conf ] && echo exists' | grep -q exists; then
        echo "==> Control plane already initialized, skipping"
        return 0
    fi

    echo "==> Initializing control plane on $CP_HOSTNAME"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" bash <<ENDSSH
sudo kubeadm init \\
    --pod-network-cidr=${POD_CIDR} \\
    --service-cidr=${SERVICE_CIDR} \\
    --apiserver-advertise-address=${ip}

# Set up kubeconfig for labuser
mkdir -p \$HOME/.kube
sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

# Apply Flannel CNI
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
ENDSSH
}

# ═══════════════════════════════════════════════════════════
# STEP 5: Join workers
# ═══════════════════════════════════════════════════════════
join_worker() {
    local worker_ip=$1 worker_hostname=$2

    # GUARD: check if node already in cluster
    local cp_ip="${CP_IP%/*}"
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${cp_ip}" "kubectl get node ${worker_hostname} &>/dev/null && echo joined" 2>/dev/null | grep -q joined; then
        echo "==> $worker_hostname already joined, skipping"
        return 0
    fi

    echo "==> Joining $worker_hostname to cluster"

    # Generate fresh token from CP
    local join_cmd
    join_cmd=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${cp_ip}" 'sudo kubeadm token create --print-join-command 2>/dev/null')

    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${worker_ip}" "sudo ${join_cmd}"
}

# ═══════════════════════════════════════════════════════════
# STEP 6: Verify
# ═══════════════════════════════════════════════════════════
verify_cluster() {
    local cp_ip="${CP_IP%/*}"
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║  CLUSTER STATUS                      ║"
    echo "╚══════════════════════════════════════╝"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${cp_ip}" 'kubectl get nodes -o wide'
    echo ""
    echo "==> Pods (all namespaces):"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${cp_ip}" 'kubectl get pods -A'
}

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════╗"
echo "║  kubeadm-lab cluster rebuild         ║"
echo "║  Template: $TEMPLATE_ID              ║"
echo "║  CP:  $CP_HOSTNAME  ($CP_IP)         ║"
echo "║  Workers: $WORKER_COUNT              ║"
echo "╚══════════════════════════════════════╝"

# Wait for all VMs to boot
wait_for_ssh "${CP_IP%/*}" "$CP_HOSTNAME"
for ((i=0; i<WORKER_COUNT; i++)); do
    worker_ip="192.168.0.$((WORKER_START_IP + i))"
    worker_hostname="${WORKER_PREFIX}$((i+1))"
    wait_for_ssh "$worker_ip" "$worker_hostname"
done

# Node setup (containerd + kubeadm) on all nodes
setup_node "${CP_IP%/*}" "$CP_HOSTNAME"
for ((i=0; i<WORKER_COUNT; i++)); do
    worker_ip="192.168.0.$((WORKER_START_IP + i))"
    worker_hostname="${WORKER_PREFIX}$((i+1))"
    setup_node "$worker_ip" "$worker_hostname"
done

# Init control plane + Flannel
init_control_plane "${CP_IP%/*}"

# Join workers
for ((i=0; i<WORKER_COUNT; i++)); do
    worker_ip="192.168.0.$((WORKER_START_IP + i))"
    worker_hostname="${WORKER_PREFIX}$((i+1))"
    join_worker "$worker_ip" "$worker_hostname"
done

# Verify
verify_cluster

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Cluster ready.                      ║"
echo "║  ssh labuser@${CP_IP%/*}             ║"
echo "║  kubectl get nodes                   ║"
echo "╚══════════════════════════════════════╝"

