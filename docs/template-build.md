# Building the Debian 13 cloud-init template (VMID 9997)

Template `k8s-debian13-cloudinit` is the base image for the kubeadm lab cluster.
Clones boot with cloud-init handling SSH key injection and static IP assignment,
so `rebuild.sh` can go from `qm clone` to SSH-reachable node with zero console work.

## Why a DIY template instead of a stock cloud image

There are two paths to a cloud-init template: download a prebuilt cloud image
(e.g. Debian GenericCloud qcow2, cloud-init preinstalled), or take an
installer-built VM and add cloud-init to it. This template uses the second path —
it was built from an existing Debian 13 VM (VMID 9003) that already had
`cloud-init` and `qemu-guest-agent` installed. Cloud-init doesn't care how it got
installed; it just needs to be present and find the Proxmox NoCloud drive at boot.

## 1. Clone the base VM and add the cloud-init drive

```bash
qm clone 9003 9998 --name temp-cloudinit --full
qm set 9998 --ide2 local-lvm:cloudinit
qm set 9998 --ciuser labuser
qm set 9998 --cipassword <redacted>   # console recovery only — SSH is key-based
qm template 9998
```

The cloud-init drive (`ide2`) is a small ISO Proxmox regenerates on every VM
start, containing user-data, meta-data, and network-config built from the VM's
`--ci*` and `--ipconfig*` options.

## 2. Smoke test — and the first failure

```bash
qm clone 9998 9997 --name test-cloudinit --full
qm set 9997 --ipconfig0 "ip=192.168.0.99/24,gw=192.168.0.1"
qm set 9997 --sshkey /root/.ssh/id_rsa.pub
qm set 9997 --ciuser labuser
qm start 9997
```

Result: **SSH key injection worked, static IP didn't.** `ssh labuser@192.168.0.99`
returned "No route to host." Querying the guest through qemu-guest-agent
(no network required):

```bash
qm guest cmd 9997 network-get-interfaces
```

showed the VM sitting on a DHCP address (192.168.0.136), not the assigned .99.

## 3. Root cause

Two leftovers from the base VM's manual-configuration era:

1. `/etc/cloud/cloud.cfg.d/99-proxmox.cfg` contained `network: config: disabled` —
   originally the right call for hand-configured VMs, but it tells cloud-init to
   ignore the network-config Proxmox sends via `--ipconfig0` entirely.
2. `/etc/network/interfaces` had a hardcoded `iface ens18 inet dhcp` stanza, so
   Debian's ifupdown fell back to DHCP.

Lesson: cloud-init applying *some* config (SSH keys) and skipping other config
(network) usually means a per-module override, not a broken datasource.

## 4. Fix — applied on the running test VM

```bash
# Let cloud-init manage networking again
sudo sed -i 's/network:/#network:/; s/  config: disabled/#  config: disabled/' \
    /etc/cloud/cloud.cfg.d/99-proxmox.cfg

# Remove the DHCP stanza so cloud-init's rendered config wins
sudo sed -i '/^allow-hotplug ens18/d; /^iface ens18 inet dhcp/d' /etc/network/interfaces
```

## 5. Pre-template cleanup

Run before every conversion to template — skipping this is how clones end up
with duplicate machine-ids (DHCP conflicts) and identical SSH host keys:

```bash
sudo cloud-init clean --logs --machine-id
sudo rm -f /etc/ssh/ssh_host_*
sudo poweroff
```

`cloud-init clean` resets the per-instance state so clones run a full first-boot
provisioning pass. Regenerating host keys per-clone is also why `teardown.sh`
purges known_hosts entries.

## 6. Template the FIXED VM, retire the broken one

The fix lives in 9997, so 9997 becomes the template — not the original 9998:

```bash
qm template 9997
qm destroy 9998
qm set 9997 --name k8s-debian13-cloudinit
```

## 7. Verify with a fresh clone

```bash
qm clone 9997 9995 --name test-v2 --full
qm set 9995 --ipconfig0 "ip=192.168.0.99/24,gw=192.168.0.1"
qm set 9995 --sshkey /root/.ssh/id_rsa.pub
qm set 9995 --ciuser labuser
qm start 9995
# ~60s later:
ssh labuser@192.168.0.99 'hostname; ip -br addr | grep ens18'
```

Passwordless SSH to the assigned static IP: template verified. `rebuild.sh`
points at `TEMPLATE_ID=9997` via `config.sh`.

## Gotchas summary

- `network: config: disabled` silently discards Proxmox `--ipconfig0` while other
  cloud-init modules (users, SSH keys) still run — partial success is the tell.
- Leftover `iface <nic> inet dhcp` stanzas in `/etc/network/interfaces` fight
  cloud-init's rendered config on Debian/ifupdown.
- Always `cloud-init clean --machine-id` + wipe SSH host keys before templating.
- Fix bugs on the clone you can reach, then template *that* VM — don't re-template
  the broken ancestor.
- `qm guest cmd <vmid> network-get-interfaces` is the hypervisor-level escape
  hatch when a guest is unreachable over the network.
