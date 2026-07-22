#!/bin/bash 
# teardown.sh --- Proxmox level kubeadm cluster destroyer
# Runs ON the Proxmox host (pve-01). Drains and deleted nodes, followed by kubeadm reset and destroys created VMS
set -euo pipefail
source ./config.sh

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# SECTION 1 - Parse optional --destroy flag. Default: soft reset (kubeadm reset, vms stay alive)
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
DESTROY_VMS=false

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# SECTION 2 - Drain + delete workers from CP, then reset CP
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
ssh labuser@$CP_IP "                                                                                                                                      
    for node in \$(kubectl get nodes -o name | grep worker); do                                                                                           
        kubectl drain \$node --ignore-daemonsets --delete-emptydir-data --timeout=60s                                                                     
        kubectl delete \$node                                                                                                                             
    done                                                                                                                                                  
    sudo kubeadm reset -f                                                                                                                                 
"

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# SECTION 3 - Reset each worker individually
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
echo "==> Resetting workers..."                                                                                                                           
for ((i=0; i<WORKER_COUNT; i++)); do                                                                                                                      
    worker_ip="${SUBNET_PREFIX}.$((WORKER_IP_START + i))"                                                                                                        
    ssh labuser@$worker_ip 'sudo kubeadm reset -f' 2>/dev/null || echo "  worker $i unreachable (may be already down)"                                    
done

# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# SECTION 4 - Optionally destroy VMs 
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
if $DESTROY_VMS; then                                                                                                                                     
    echo "==> Destroying VMs..."                                                                                                                          
    qm stop $CP_VMID && qm destroy $CP_VMID                                                                                                               
    for ((i=0; i<WORKER_COUNT; i++)); do                                                                                                                  
        qm stop $((WORKER_START_VMID + i))                                                                                                                
        qm destroy $((WORKER_START_VMID + i))                                                                                                             
    done                                                                                                                                                  
    echo "==> All VMs destroyed. Run rebuild.sh to start fresh."                                                                                          
else                                                                                                                                                      
    echo "==> Cluster reset. VMs still running. Run rebuild.sh to re-init."                                                                               
fi                                

# Purge stale host keys — next rebuild gets fresh keys on these IPs
echo "==> Removing stale SSH host keys"
ssh-keygen -R "${CP_IP%/*}" 2>/dev/null || true
for ((i=0; i<WORKER_COUNT; i++)); do
    ssh-keygen -R "${SUBNET_PREFIX}.$((WORKER_START_IP + i))" 2>/dev/null || true
done
