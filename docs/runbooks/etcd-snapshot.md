# RUNBOOK

## Creating an ETCD snapshot and restoring

### PRE-REQUISITES

1. install etcdctl and etcdutl add to path
    - `git clone https://github.com/etcd-io/etcd.git` # will install latest version PIN TO MATCHING ETCD CLUSTER VERSION
    - `cd etcd`
    - `make build` OR `./build`
    - `sudo install -m 755 bin/etcd bin/etcdctl bin/etcdutl /usr/local/bin` # adds etcd utilities to PATH
    - `etcd --version` # tests to ensure etcd is in your path     

### TASK 1 - CREATE SNAPSHOT

1. `export ETCDCTL_API=3`
2. ```bash
    sudo etcdctl snapshot save /tmp/etcd-snapshot.db \
    --endpoints="https://127.0.0.1:2379" \
    --cacert="/etc/kubernetes/pki/etcd/ca.crt" \
    --cert="/etc/kubernetes/pki/etcd/server.crt" \
    --key="/etc/kubernetes/pki/etcd/server.key"
    ```
3. verify snapshot
    - `sudo etcdutl snapshot status -w table /tmp/etcd-snapshot.db`

### TASK 2 - RESTORE SNAPSHOT

1. Restore snapshot in dedicated data directory
    ```bash
    sudo mkdir -p /var/lib/etcd-backup
    sudo etcdutl snapshot restore --data-dir /var/lib/etcd-backup /tmp/etcd-snapshot.db
    ```
2. edit static pod manifest for etcd and point it to backup directory location.
`sudo vi /etc/kubernetes/manifests/etcd.yaml`
    ```bash

    # Edit the following:
    volumes:
    - hostPath:
        path: /etc/kubernetes/pki/etcd
        type: DirectoryOrCreate
        name: etcd-certs
    - hostPath:
        path: /var/lib/etcd-backup # <----- BACKUP PATH HERE
        type: DirectoryOrCreate
        name: etcd-data
    status: {}
    ```
3. Etcd pod will restart and data will be restored after about a minute or two.

### MISSION ACCOMPLISHED
