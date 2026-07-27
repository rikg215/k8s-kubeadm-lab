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

The biggest gain is turning all this work into clean repeatable scripts so that I can quickly teardown and recreate the cluster from scatch

### 2 executable scripts that make everything easier

I spent a lot of time ensuring that I had workable proxmox templates as a first step to ensure the rebuild script had a starting point to choose from. The main idea was to have one config file that set all appropriate and required parameters for the rebuild and teardown script.

### Rebuild Script

The script runs on the Proxmox host itself and sources config.sh at the top, so every value like VMIDs, IPs, and versions lives in one place.

The first component is the clone_vm function. Inside it is an idempotency guard to avoid duplicate VMs or failed attempts at creating a VM with a VMID that's already taken. I used a conditional if statement to achieve this. The trick is that bash if branches on the exit code of the command it's given, not its output. So the guard runs qm status on the Proxmox host with all output silenced, and if it exits 0 (meaning the VMID exists) the "then" block executes: it tells the user the VM already exists, runs qm start with stderr silenced and || true tacked on so the command always evaluates to true and set -e doesn't kill the script if the VM was already running, then returns early out of the function. If qm status errors, the condition is false, so bash skips the then block and falls through to the clone logic, which does a full clone from the template and applies the cloud-init settings (static IP, gateway, SSH key, user) pulled from the config file. The function gets called once for the control plane and then in a loop for the workers, with each worker's VMID, IP, and hostname calculated by offsetting from the start values in config.

Next is wait_for_ssh. Cloning and starting a VM doesn't mean it's usable — cloud-init has to finish on first boot before SSH is up. This function uses an until loop that keeps trying to SSH in and run a throwaway echo. Same exit code logic as the guard: the loop only breaks once SSH actually succeeds. It's capped at 60 attempts with a 5 second sleep between each, so if a node isn't reachable after about 5 minutes the script errors out with a hint to check the console instead of hanging forever.

Then setup_node does the actual node prep over SSH using a heredoc. It has its own idempotency guard — this time checking whether kubeadm is already on the node with command -v, echoing a marker string and grepping for it, since I care about the remote command's result and not the SSH session itself. If the node is fresh, the heredoc runs the full kubeadm prerequisite list: disable swap and comment it out of fstab, load the overlay and br_netfilter kernel modules, set the ip_forward and bridge-nf-call-iptables sysctls, install containerd from Docker's apt repo, flip SystemdCgroup to true in the containerd config, then install kubeadm/kubelet/kubectl from the v1.36 pkgs.k8s.io repo and apt-mark hold them so unattended upgrades can't version-drift the cluster. The heredoc uses a quoted delimiter ('ENDSSH') so nothing inside it gets expanded locally — everything runs literally on the remote node.

init_control_plane runs kubeadm init on the CP only. Its guard checks for /etc/kubernetes/admin.conf, which only exists after a successful init, so re-running the script won't try to init twice. This heredoc is unquoted on purpose — I want {POD_CIDR}, {SERVICE_CIDR}, and ${ip} expanded from config before the commands ship to the remote host, while things like \$HOME are escaped so they expand remotely. After init it copies the admin kubeconfig to labuser and applies the Flannel manifest, pinned to a specific version in config for reproducible rebuilds.

join_worker handles cluster joining. The guard here is different from the others: instead of asking the worker anything, it asks the control plane whether the node name already shows up in kubectl get nodes. If not, it generates a fresh join command on the CP with kubeadm token create --print-join-command, captures it into a variable with command substitution, and runs it on the worker with sudo. Generating the token fresh each run means I never deal with expired tokens on rebuilds.

verify_cluster just SSHes to the CP and prints kubectl get nodes -o wide and all pods across namespaces so I get immediate confirmation the cluster came up healthy.

The main section at the bottom is straight orchestration: clone everything, wait for SSH on everything, set up every node, init the CP, join the workers, verify. Every phase loops over the workers using the same offset math, and because every function is guarded, the whole script is safe to re-run from the top — it picks up wherever the last run died.

### Config

Config (config.sh)

config.sh is the single source of truth shared by rebuild and teardown. It defines the lab subnet and gateway, the cloud-init template ID, the SSH user/key/options, the control plane's hostname/IP/VMID, and the worker count plus starting VMID and IP that the loops offset from. It also pins the pod and service CIDRs and the Flannel version. The point is that scaling the lab from 2 workers to 4, or moving it to a different subnet, is a one-line edit here neither script gets touched.

### Teardown Script

Teardown (teardown.sh)

teardown.sh is the destroyer and it's two-speed. By default it does a soft reset: it SSHes to the control plane and, for each worker node it finds in the cluster, drains it and deletes it from the API, then runs kubeadm reset -f on the CP. That whole block has an || echo fallback so if the CP is already dead the teardown keeps going instead of aborting. Then it loops through the workers by IP and runs kubeadm reset -f on each one individually, again with fallbacks for unreachable nodes. The VMs stay alive, so a rebuild afterward skips straight past cloning and node setup and just re-inits the cluster.

Passing --destroy flips a boolean parsed from $1 (with ${1:-} so set -u doesn't blow up when no argument is given) and adds a hard phase: stop and qm destroy the CP and every worker VM, wiping the lab back to nothing.

Either way, the last step purges the stale SSH host keys for every lab IP with ssh-keygen -R. Fresh clones generate new host keys on the same IPs, so without this the next rebuild would trip host key verification errors.

## Architecture Diagram

```text
┌────────────────────────────────────────────────────────┐
│                    Proxmox (R710)                      │
│                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  k8s-cp-1    │  │ k8s-worker-1 │  │ k8s-worker-2 │  │
│  │  2vCPU / 4GB │  │ 2vCPU / 4GB  │  │ 2vCPU / 4GB  │  │
│  │ ControlPlane │  │    Worker    │  │    Worker    │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         └────────────┬────┴─────────────────┘          │
│               Flannel CNI (VXLAN)                      │
│                                                        │
│  kubeadm init config:                                  │
│    podSubnet:     10.244.0.0/16                        │
│    serviceSubnet: 10.96.0.0/12                         │
└────────────────────────────────────────────────────────┘
```


