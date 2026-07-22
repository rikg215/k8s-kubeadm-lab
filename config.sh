#!/usr/bin/env bash
# config.sh — shared configuration for rebuild.sh and teardown.sh
# Source: source ./config.sh
# Edit ONCE. Both scripts read from here.

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# NETWORK
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# Network — single source of truth for the lab subnet
SUBNET_PREFIX="192.168.0"
CIDR_SUFFIX="/24"
GATEWAY="${SUBNET_PREFIX}.1"
BRIDGE="vmbr0"

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# PROXMOX / TEMPLATE
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
TEMPLATE_ID=9997                     # k8s-debian13-cloudinit (cloud-init + SSH key + static IP)
SSH_USER="labuser"                   # cloud-init injects pubkey for this user
SSH_KEY="/root/.ssh/id_rsa.pub"      # Proxmox root's RSA key
SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# CONTROL PLANE
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
CP_HOSTNAME="k8s-cp-01-hl"
CP_IP="${SUBNET_PREFIX}.64${CIDR_SUFFIX}" # CIDR notation for qm set --ipconfig0
CP_VMID=604

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# WORKERS
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
WORKER_COUNT=2
WORKER_PREFIX="k8s-w"
WORKER_START_VMID=605
WORKER_START_IP=65                   # first worker gets 192.168.0.65, next .66, etc.

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# KUBEADM
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
POD_CIDR="10.244.0.0/16"             # Flannel default
SERVICE_CIDR="10.96.0.0/12"

# CNI version — pin for reproducible rebuilds; check flannel-io/flannel releases before bumping
FLANNEL_VERSION="v0.28.7"
