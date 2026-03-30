# k8s-lab VM Setup

This directory contains the Vagrantfile and provisioning scripts for a local Kubernetes lab cluster running on VirtualBox.

## VM Layout


| VM            | Hostname    | IP            | RAM     | CPUs | Role                                                                     |
| ------------- | ----------- | ------------- | ------- | ---- | ------------------------------------------------------------------------ |
| `k3s-master`  | k3s-master  | 192.168.56.11 | 3072 MB | 2    | k3s control plane                                                        |
| `k3s-worker1` | k3s-worker1 | 192.168.56.12 | 2048 MB | 1    | k3s worker node                                                          |
| `k3s-worker2` | k3s-worker2 | 192.168.56.13 | 2048 MB | 1    | k3s worker node                                                          |
| `runner-ci`   | runner-ci   | 192.168.56.10 | 2048 MB | 2    | GitHub Actions runner + container registry + monitoring/dashboard deploy |
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

## Networking

### Architecture

All HTTP traffic flows through a single MetalLB virtual IP into the NGINX Ingress Controller, which routes requests by hostname:

```
macOS Host ──▶ MetalLB VIP (192.168.56.200) ──▶ NGINX Ingress Controller
                                                    ├─ grafana.k8s.lab   → Grafana   (monitoring)
                                                    ├─ headlamp.k8s.lab  → Headlamp  (dashboard)
                                                    └─ app.k8s.lab       → App Services
```


| Component                    | Namespace        | Purpose                                             |
| ---------------------------- | ---------------- | --------------------------------------------------- |
| **MetalLB**                  | `metallb-system` | Assigns VIPs from `192.168.56.200-220` via L2/ARP   |
| **NGINX Ingress Controller** | `ingress-nginx`  | Routes HTTP traffic by hostname to backend services |


### DNS Setup (macOS Host)

Add the following to `/etc/hosts` on your macOS host so that browsers can resolve the `.k8s.lab` hostnames to the MetalLB VIP:

```bash
sudo sh -c 'echo "192.168.56.200 grafana.k8s.lab headlamp.k8s.lab app.k8s.lab" >> /etc/hosts'
```

Or manually add this line to `/etc/hosts`:

```
192.168.56.200 grafana.k8s.lab headlamp.k8s.lab app.k8s.lab
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

