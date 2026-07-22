#!/usr/bin/env bash
# config.sh — shared configuration for rebuild.sh and teardown.sh
# Source: source ./config.sh
# Edit ONCE. Both scripts read from here.

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# PROXMOX / TEMPLATE
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
TEMPLATE_ID=9997                     # k8s-debian13-cloudinit (cloud-init + SSH key + static IP)
SSH_USER="labuser"                   # cloud-init injects pubkey for this user
SSH_KEY="/root/.ssh/id_rsa.pub"      # Proxmox root's RSA key

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# CONTROL PLANE
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
CP_HOSTNAME="k8s-cp-01-hl"
CP_IP="192.168.0.64/24"              # CIDR notation for qm set --ipconfig0
CP_VMID=601

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# WORKERS
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
WORKER_COUNT=2
WORKER_PREFIX="k8s-w"
WORKER_START_VMID=602
WORKER_START_IP=65                   # first worker gets 192.168.0.62, next .63, etc.

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# NETWORK
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
GATEWAY="192.168.0.1"
BRIDGE="vmbr0"

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# KUBEADM
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
POD_CIDR="10.244.0.0/16"             # Flannel default
SERVICE_CIDR="10.96.0.0/12"

