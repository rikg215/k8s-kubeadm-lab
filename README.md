# k8s-kubeadm-lab

Documentation on process to build homelab k8s cluster

## Why?

### Demonstration of proficiency:

- Creation of a reusable "battle-tested" Proxmox template
- Using Proxmox to clone template into any number of virtual machines
- Ensuring necessary packages are baked into template
- Configuring VMs with proper hostname and network configurations after creation
- Installing a CRI (Containerd) with basic configuration
- Installing a CNI (Flannel) with basic configuration
- Utilizing Kubeadm and kubernetes documentation to provision a control plane node and join workers to said node

### Practice makes Perfect

This is just yet another rep for me with many more to come

## Making it repeatable

The biggest gain is turning all this work into clean repeatable scripts so that I can quickly recreate teardown and recreate the cluster from scatch

## Architecture Diagram

─────────────────────────────────────┐

│ Proxmox (R710) │

│ ┌──────────┐ ┌────────┐ ┌──────┐│

│ │k8s-cp-1│ │k8s-worker-1│ │k8s-worker-2││

│ │2vCPU/4GB │ │2vCPU/4G│ │2vCPU/4││

│ │ControlPl │ │Worker │ │Worker ││

│ └──────────┘ └────────┘ └──────┘│

│ │ Flannel CNI (VXLAN) │

│ └──────────┬──────────────────┘

│ │

│ kubeadm init config:

│ podSubnet: 10.244.0.0/16

│ serviceSubnet: 10.96.0.0/12

└─────────────────────────────────────┘


