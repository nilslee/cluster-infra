# k8s-lab VM Setup

This directory contains the Vagrantfile and provisioning scripts for a local Kubernetes lab cluster running on VirtualBox.

## VM Layout


| VM            | Hostname    | IP            | RAM     | CPUs | Role                                                                     |
| ------------- | ----------- | ------------- | ------- | ---- | ------------------------------------------------------------------------ |
| `k3s-master`  | k3s-master  | 192.168.56.11 | 3072 MB | 2    | k3s control plane                                                        |
| `k3s-worker1` | k3s-worker1 | 192.168.56.12 | 2048 MB | 1    | k3s worker node                                                          |
| `k3s-worker2` | k3s-worker2 | 192.168.56.13 | 2048 MB | 1    | k3s worker node                                                          |
| `runner-ci`   | runner-ci   | 192.168.56.10 | 2048 MB | 2    | GitHub Actions runner + container registry + monitoring/dashboard/Argo CD deploy |
| **Total**     |             |               |         |      |                                                                          |


## What Gets Provisioned

### runner-ci (192.168.56.10)

- **Docker Engine** — used by workflows to build and push images
- **registry:2** — local container registry listening on port 5000; k3s nodes pull from `192.168.56.10:5000`
- **kubectl** — talks to the k3s API server via `/vagrant/kubeconfig` (written by the master provisioning script)
- **Helm** — used to deploy the monitoring stack and available for interactive use
- **GitHub Actions Runner** — self-hosted runner agent registered to this repo with the label `k8s-lab`
- **Networking stack** — MetalLB (L2) + NGINX Ingress Controller deployed via `setup-networking.sh` (second provisioner)
- **Monitoring stack** — deployed via `setup-monitoring.sh` (third provisioner) after networking is ready
- **Headlamp dashboard** — deployed via `setup-dashboard.sh` (fourth provisioner) after the monitoring stack
- **Argo CD** — deployed via `setup-argocd.sh` (fifth provisioner); watches `cluster-infra` on GitHub and syncs all manifests under `k8s/` to the cluster automatically

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

Vagrant provisions the VMs in order: `k3s-master` → `k3s-worker1` → `k3s-worker2` → `runner-ci`. The k3s cluster is fully up before `runner-ci` provisions, so the monitoring install in `setup-monitoring.sh` can run without waiting. The kubeconfig and join token are exchanged automatically through the shared `/vagrant` folder.

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

All cluster changes flow through a single path: **CI builds the image → CI bumps the tag in Git → Argo CD syncs the cluster**. No workflow ever runs `kubectl` against the cluster directly.

### App repos (`deploy.yml` — Build and Promote)

Triggered on every push to `main`. Two steps:

1. **Build and push** — `docker build` + `docker push` to the local registry
2. **Git bump** — clones `cluster-infra`, runs `kustomize edit set image` to update `newTag` in `k8s/apps/<app>/kustomization.yaml`, commits, and pushes

```
on: push → docker build → docker push → kustomize edit set image → git push cluster-infra
```

Argo CD detects the new commit and rolls out the updated image automatically.

**Required secret:** `INFRA_REPO_PAT` — a GitHub PAT (or fine-grained token) with write access to the `cluster-infra` repo, stored as a repository secret in each app repo.

Runs on: `[self-hosted, k8s-lab]`

### Manual Trigger

The workflow includes `workflow_dispatch`, which adds a **Run workflow** button in the GitHub Actions UI. You can also trigger via the GitHub CLI:

```bash
gh workflow run deploy.yml --repo <yourname>/<repo>
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

## Monitoring

The cluster ships with a full observability stack deployed automatically during provisioning.

### Components


| Component              | Chart                   | Description                                          |
| ---------------------- | ----------------------- | ---------------------------------------------------- |
| **Prometheus**         | `kube-prometheus-stack` | Metrics collection and storage (3-day retention)     |
| **Grafana**            | `kube-prometheus-stack` | Dashboards and visualisations                        |
| **node-exporter**      | `kube-prometheus-stack` | Per-node hardware/OS metrics (DaemonSet)             |
| **kube-state-metrics** | `kube-prometheus-stack` | Kubernetes object metrics                            |
| **Loki**               | `loki`                  | Log aggregation (SingleBinary mode, 3-day retention) |
| **Promtail**           | `promtail`              | Log shipping from all nodes (DaemonSet)              |


All components run in the `monitoring` namespace.

### Accessing Grafana

Open Grafana in your browser at **[http://grafana.k8s.lab](http://grafana.k8s.lab)** (routed through NGINX Ingress via MetalLB VIP).
Default credentials: **admin / admin**
Both Prometheus and Loki are pre-configured as datasources.

### Dashboards

Two sets of dashboards are pre-provisioned automatically.

**Kubernetes compute dashboards** (built into `kube-prometheus-stack`) — metrics-focused views per cluster, namespace, node, pod, and workload. Found under **Dashboards → Default**.

**Kubernetes Views** — a Grafana Cloud-style drilldown hierarchy for cluster inventory. Found under **Dashboards → Kubernetes Views**.


| Dashboard                        | Grafana ID | What it shows                                                      |
| -------------------------------- | ---------- | ------------------------------------------------------------------ |
| Kubernetes / System / API Server | 15761      | API server request rates, latency, and errors                      |
| Kubernetes / System / CoreDNS    | 15762      | CoreDNS query rates and latency                                    |
| Kubernetes / Views / Global      | 15757      | Cluster-level overview: node/pod counts, CPU & memory by namespace |
| Kubernetes / Views / Namespaces  | 15758      | Per-namespace workload list and resource usage                     |
| Kubernetes / Views / Nodes       | 15759      | Per-node pod list, CPU/memory/disk                                 |
| Kubernetes / Views / Pods        | 15760      | Per-pod container list, restarts, resource limits                  |


Start at **Views / Global** and use the namespace/node/pod dropdowns at the top of each dashboard to drill down. These dashboards are loaded from grafana.com at Grafana startup (requires internet access from the VM).

### Re-deploying / Updating the Monitoring Stack

If you change the Helm values files (`cluster-infra/monitoring/*.yaml`), re-run the deploy script from the runner VM:

```bash
vagrant ssh runner-ci
KUBECONFIG=/vagrant/kubeconfig bash /vagrant/vm-setup/setup-monitoring.sh
```

The script is idempotent (`helm upgrade --install`), so it is safe to run multiple times.

### Memory Requirements

The monitoring workloads require more RAM than a plain k3s cluster. The updated VM sizes are:

- `k3s-master`: 3072 MB (was 2048 MB)
- `k3s-worker1`: 2048 MB (was 1024 MB)
- `k3s-worker2`: 2048 MB (was 1024 MB)

## Dashboard

The cluster includes [Headlamp](https://headlamp.dev/), a modern Kubernetes web UI deployed automatically during provisioning.

### Accessing Headlamp

Open Headlamp in your browser at **[http://headlamp.k8s.lab](http://headlamp.k8s.lab)** (routed through NGINX Ingress via MetalLB VIP).

### Authentication

Headlamp requires a **service account bearer token** to log in. The Helm chart creates a service account named `headlamp` in the `dashboard` namespace with cluster-wide read access.

Generate a login token:

```bash
kubectl create token headlamp -n dashboard
```

Copy the token output and paste it into the Headlamp login screen.

### Re-deploying / Updating Headlamp

If you change the Helm values (`cluster-infra/dashboard/headlamp-values.yaml`), re-run the deploy script from the runner VM:

```bash
vagrant ssh runner-ci
KUBECONFIG=/vagrant/kubeconfig bash /vagrant/vm-setup/setup-dashboard.sh
```

The script is idempotent (`helm upgrade --install`), so it is safe to run multiple times.

---

## Argo CD (GitOps)

The cluster uses [Argo CD](https://argo-cd.readthedocs.io/) as the single writer to the cluster. All desired state lives in Git; no workflow ever runs `kubectl apply` or `kubectl set image` directly.

### How It Works

```
Developer push → CI builds image → CI bumps newTag in cluster-infra → Argo CD detects commit → Argo CD syncs cluster
```

Argo CD watches the `cluster-infra` GitHub repo and reconciles the cluster whenever a new commit lands on `main`. Two Applications are configured:

| Application  | Path                  | Namespace | Sync policy          |
| ------------ | --------------------- | --------- | -------------------- |
| `namespaces` | `k8s/namespaces/`     | (various) | Auto-sync + selfHeal |
| `my-redis`   | `k8s/apps/my-redis/`  | `k8s-lab` | Auto-sync + selfHeal |

### Accessing Argo CD

Open the Argo CD UI in your browser at **[http://argocd.k8s.lab](http://argocd.k8s.lab)** (routed through NGINX Ingress via MetalLB VIP).

**Username:** `admin`

**Initial password:** Printed at the end of `setup-argocd.sh` provisioning output. Retrieve it any time with:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Change the password after first login via **Settings → Account → Update Password**, then delete the bootstrap secret:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

### Adding a New Application

1. Create a Kustomize directory under `cluster-infra/k8s/apps/<app-name>/` with `kustomization.yaml`, `deployment.yaml`, etc.
2. Add a new `Application` manifest to `cluster-infra/argocd/applications/<app-name>.yaml` (use `my-redis.yaml` as a template).
3. Apply the Application CR (or let Argo CD pick it up on the next sync if you are using an App of Apps pattern):

```bash
kubectl apply -f cluster-infra/argocd/applications/<app-name>.yaml
```

### Re-deploying / Updating Argo CD

If you change the Helm values (`cluster-infra/argocd/argocd-values.yaml`), re-run the deploy script from the runner VM:

```bash
vagrant ssh runner-ci
KUBECONFIG=/vagrant/kubeconfig bash /vagrant/vm-setup/setup-argocd.sh
```

The script is idempotent (`helm upgrade --install`), so it is safe to run multiple times.

### Memory Considerations

Argo CD adds ~300–500 MB of RAM. The `k3s-master` VM has 3072 MB which is sufficient. Monitor usage with:

```bash
kubectl top pods -n argocd
```

---

## Networking

### Architecture

All HTTP traffic flows through a single MetalLB virtual IP into the NGINX Ingress Controller, which routes requests by hostname:

```
macOS Host ──▶ MetalLB VIP (192.168.56.200) ──▶ NGINX Ingress Controller
                                                    ├─ grafana.k8s.lab   → Grafana      (monitoring)
                                                    ├─ headlamp.k8s.lab  → Headlamp     (dashboard)
                                                    ├─ argocd.k8s.lab    → Argo CD      (argocd)
                                                    └─ app.k8s.lab       → App Services
```


| Component                    | Namespace        | Purpose                                             |
| ---------------------------- | ---------------- | --------------------------------------------------- |
| **MetalLB**                  | `metallb-system` | Assigns VIPs from `192.168.56.200-220` via L2/ARP   |
| **NGINX Ingress Controller** | `ingress-nginx`  | Routes HTTP traffic by hostname to backend services |


### DNS Setup (macOS Host)

Add the following to `/etc/hosts` on your macOS host so that browsers can resolve the `.k8s.lab` hostnames to the MetalLB VIP:

```bash
sudo sh -c 'echo "192.168.56.200 grafana.k8s.lab headlamp.k8s.lab argocd.k8s.lab app.k8s.lab" >> /etc/hosts'
```

Or manually add this line to `/etc/hosts`:

```
192.168.56.200 grafana.k8s.lab headlamp.k8s.lab argocd.k8s.lab app.k8s.lab
```

`192.168.56.200` is the first address MetalLB assigns from its pool to the NGINX Ingress Controller's LoadBalancer Service.

### Network Notes

### Network Notes

- All VMs share a VirtualBox host-only network (`192.168.56.0/24`)
- The container registry is **insecure** (plain HTTP); `registries.yaml` on each k3s node tells containerd to allow it
- The runner accesses the k3s API at `https://192.168.56.11:6443` using `/vagrant/kubeconfig`
- Workflows reference the registry as `192.168.56.10:5000/<image-name>`
- MetalLB VIP pool (`192.168.56.200-220`) sits outside the static VM range (`.10-.13`) to avoid collisions
- k3s's bundled ServiceLB and Traefik are disabled (`--disable servicelb --disable traefik`) in favour of MetalLB + NGINX

