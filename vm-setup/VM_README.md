# k8s-lab VM Setup

This directory contains the Vagrantfile and provisioning scripts for a local Kubernetes lab cluster running on VirtualBox.

## VM Layout

| VM           | Hostname     | IP              | RAM    | CPUs | Role                                    |
|--------------|--------------|-----------------|--------|------|-----------------------------------------|
| `runner-ci`  | runner-ci    | 192.168.56.10   | 2048 MB | 2   | GitHub Actions runner + container registry |
| `k3s-master` | k3s-master   | 192.168.56.11   | 2048 MB | 2   | k3s control plane                       |
| `k3s-worker1`| k3s-worker1  | 192.168.56.12   | 1024 MB | 1   | k3s worker node                         |
| `k3s-worker2`| k3s-worker2  | 192.168.56.13   | 1024 MB | 1   | k3s worker node                         |
| **Total**    |              |                 | **6144 MB** | **6** |                                    |

## What Gets Provisioned

### runner-ci (192.168.56.10)
- **Docker Engine** — used by workflows to build and push images
- **registry:2** — local container registry listening on port 5000; k3s nodes pull from `192.168.56.10:5000`
- **kubectl** — talks to the k3s API server via `/vagrant/kubeconfig` (written by the master provisioning script)
- **GitHub Actions Runner** — self-hosted runner agent registered to this repo with the label `k8s-lab`

### k3s-master (192.168.56.11)
- Installs k3s server
- Writes `/etc/rancher/k3s/registries.yaml` to trust the local insecure registry at `192.168.56.10:5000`
- Exports `/vagrant/token` (used by workers to join the cluster)
- Exports `/vagrant/kubeconfig` with the server URL rewritten to `192.168.56.11:6443` so the runner VM can reach the API server

### k3s-worker1 / k3s-worker2 (192.168.56.12–13)
- Installs k3s agent and joins the master
- Writes the same `registries.yaml` so they can pull images from `192.168.56.10:5000`

## Prerequisites

- [Vagrant](https://www.vagrantup.com/) ≥ 2.3
- [VirtualBox](https://www.virtualbox.org/) ≥ 7.0
- A GitHub account with a repository (or organisation) to register the runner against

## Starting the Cluster

```bash
cd cluster-infra/vm-setup
vagrant up
```

Vagrant provisions the VMs in order: `runner-ci` → `k3s-master` → `k3s-worker1` → `k3s-worker2`. The kubeconfig and join token are exchanged automatically through the shared `/vagrant` folder.

To bring up a single VM:

```bash
vagrant up runner-ci
vagrant up k3s-master
```

## Runner Registration (One-Time Manual Step)

The provisioning script installs the runner binary but registration requires a token from GitHub — this is intentionally a manual step to avoid storing credentials in the repo.

1. Go to your GitHub repository (or organisation) → **Settings** → **Actions** → **Runners** → **New self-hosted runner**
2. Copy the registration token shown on that page
3. SSH into the runner VM:

   ```bash
   vagrant ssh runner-ci
   ```

4. Run the configuration command (replace `<ORG_OR_REPO_URL>` and `<TOKEN>`):

   ```bash
   cd /opt/actions-runner
   ./config.sh --url https://github.com/<ORG_OR_REPO_URL> \
     --token <TOKEN> \
     --labels k8s-lab \
     --unattended
   ```

5. Install and start the runner as a systemd service so it survives reboots:

   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

### Check Runner Status

```bash
vagrant ssh runner-ci -c "systemctl status actions.runner.*"
```

Or from inside the VM:

```bash
sudo ./svc.sh status   # from /opt/actions-runner
```

## GitHub Actions Workflows

Two workflow patterns are used:

### App repos (`deploy.yml`)

Triggered on every push to `main`. Builds a Docker image, pushes it to the local registry, then does a rolling update via `kubectl set image`:

```
on: push → docker build → docker push → kubectl set image
```

Runs on: `[self-hosted, k8s-lab]`

### Infra repo (`apply.yml`)

Triggered on pushes to `main` that touch `cluster-infra/k8s/**`. Applies all manifests to the cluster:

```
on: push (k8s/**) → kubectl apply -R -f cluster-infra/k8s/
```

### Manual Trigger

Every workflow includes `workflow_dispatch`, which adds a **Run workflow** button in the GitHub Actions UI. You can also trigger via the GitHub CLI:

```bash
gh workflow run deploy.yml --repo <yourname>/<repo>
gh workflow run apply.yml  --repo <yourname>/cluster-infra
```

## Useful Commands

```bash
# SSH into a VM
vagrant ssh runner-ci
vagrant ssh k3s-master

# Check cluster node status (from k3s-master or runner-ci)
kubectl get nodes

# Check pods in the lab namespace
kubectl get pods -n k8s-lab

# Halt all VMs (keeps disk state)
vagrant halt

# Destroy all VMs
vagrant destroy -f

# Re-provision a specific VM after script changes
vagrant provision k3s-master
```

## Networking Notes

- All VMs share a VirtualBox host-only network (`192.168.56.0/24`)
- The container registry is **insecure** (plain HTTP); `registries.yaml` on each k3s node tells containerd to allow it
- The runner accesses the k3s API at `https://192.168.56.11:6443` using `/vagrant/kubeconfig`
- Workflows reference the registry as `192.168.56.10:5000/<image-name>`
