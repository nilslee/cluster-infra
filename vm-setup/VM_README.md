# k8s-lab VM Setup

This directory contains the Vagrantfile and provisioning scripts for the lab. For a project overview, quick start, service URLs, and `/etc/hosts` setup, see the [repository README](../README.md).

## VM Layout

| VM            | Hostname    | IP            | RAM     | CPUs | Role                                                                               |
| ------------- | ----------- | ------------- | ------- | ---- | ---------------------------------------------------------------------------------- |
| `k3s-master`  | k3s-master  | 192.168.56.11 | 3072 MB | 2    | k3s control plane                                                                  |
| `k3s-worker1` | k3s-worker1 | 192.168.56.12 | 2048 MB | 1    | k3s worker node                                                                    |
| `k3s-worker2` | k3s-worker2 | 192.168.56.13 | 2048 MB | 1    | k3s worker node                                                                    |
| `runner-ci`   | runner-ci   | 192.168.56.10 | 4096 MB | 2    | Jenkins CI + container registry + monitoring/dashboard/Argo CD deploy + MCP server |
| **Total**     |             |               |         |      |                                                                                    |

## What Gets Provisioned

### runner-ci (192.168.56.10)

- **Docker Engine** — used by Jenkins pipelines to build and push images
- **registry:2** — local container registry listening on port 5000; k3s nodes pull from `192.168.56.10:5000`
- **kubectl** — talks to the k3s API server via `/vagrant/kubeconfig` (written by the master provisioning script)
- **Helm** — used to deploy the monitoring stack and available for interactive use
- **Jenkins LTS** — deployed via `setup-jenkins.sh` (sixth provisioner); configured entirely via JCasC (`cluster-infra/jenkins/jcasc.yaml`) with no manual setup required
- **Networking stack** — MetalLB (L2) + NGINX Ingress Controller deployed via `setup-networking.sh` (second provisioner)
- **Monitoring stack** — deployed via `setup-monitoring.sh` (third provisioner) after networking is ready
- **Headlamp dashboard** — deployed via `setup-dashboard.sh` (fourth provisioner) after the monitoring stack
- **Argo CD** — deployed via `setup-argocd.sh` (fifth provisioner); watches `cluster-infra` on GitHub and syncs all manifests under `k8s/` to the cluster automatically
- **MCP Server** — deployed by the `mcp-server` Jenkins pipeline (not provisioned at boot); builds and runs the Spring AI MCP server as a Docker container (`mcp-server`) on port 9000, constrained to 512 MB RAM

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
- A GitHub PAT with read access to the app repos and write access to `cluster-infra` (injected as `GITHUB_PAT` env var — see [Jenkins CI](#jenkins-ci))

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

## Jenkins CI

Jenkins replaces the GitHub Actions self-hosted runner. It is fully configured at provisioning time via [Jenkins Configuration as Code (JCasC)](https://www.jenkins.io/projects/jcasc/) — no manual setup is required after `vagrant up`.

### Accessing Jenkins

Open the Jenkins UI in your browser at **[http://192.168.56.10:8080](http://192.168.56.10:8080)**.

**Username:** `admin`  
**Password:** value of `JENKINS_ADMIN_PASSWORD` set in `/etc/default/jenkins` on the VM (defaults to `admin` for lab use)

### Configuration Files

All Jenkins configuration lives in `cluster-infra/jenkins/` and is rsynced to `/jenkins/` on the VM at provisioning time:

| File                                             | Purpose                                                                      |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `jenkins/jcasc.yaml`                             | Single source of truth — security realm, credentials, job definitions        |
| `jenkins/plugins.txt`                            | Plugin manifest installed by `jenkins-plugin-cli` at provisioning time       |
| `jenkins/seed-jobs.groovy`                       | Job DSL script (also inlined in `jcasc.yaml`) that creates all pipeline jobs |
| `jenkins/pipelines/my-redis.Jenkinsfile`         | Build-and-promote pipeline for `my-redis`                                    |
| `jenkins/pipelines/redis-gui-tester.Jenkinsfile` | Build-and-promote pipeline for `redis-gui-tester`                            |
| `jenkins/pipelines/mcp-server.Jenkinsfile`       | Full-setup pipeline for the MCP server                                       |

### Credentials

Secrets are injected at provisioning time via environment variables — never stored in Git. **Required for a working CI loop:** `JENKINS_ADMIN_PASSWORD` (admin UI) and `GITHUB_PAT` (clone/push). **Optional:** `GRAFANA_USERNAME` and `GRAFANA_PASSWORD` — used by JCasC as the `mcp-grafana-loki` credential so the MCP server can send basic auth to Loki via the Grafana ingress when your lab enables it.

| Env Var                  | Jenkins Credential ID         | Required?                                           | Purpose                                                  |
| ------------------------ | ----------------------------- | --------------------------------------------------- | -------------------------------------------------------- |
| `JENKINS_ADMIN_PASSWORD` | —                             | Yes (defaults to `admin` if unset)                  | Admin UI password                                        |
| `GITHUB_PAT`             | `github-pat`                  | Yes for pipelines (defaults to `changeme` if unset) | PAT for cloning app repos and pushing to `cluster-infra` |
| `GRAFANA_USERNAME`       | `mcp-grafana-loki` (username) | No                                                  | MCP → Loki HTTP basic auth user (Grafana ingress)        |
| `GRAFANA_PASSWORD`       | `mcp-grafana-loki` (password) | No                                                  | MCP → Loki HTTP basic auth password                      |

Set these before `vagrant up` (or re-provision with them set) by exporting them on your **host** shell. The `runner-ci` **jenkins** provisioner forwards `JENKINS_ADMIN_PASSWORD`, `GITHUB_PAT`, `GRAFANA_USERNAME`, and `GRAFANA_PASSWORD` from the host into the guest so `setup-jenkins.sh` and JCasC see the same values without copying them into the VM by hand:

```bash
export JENKINS_ADMIN_PASSWORD=mysecretpassword
export GITHUB_PAT=ghp_xxxxxxxxxxxx
# Optional — only if Grafana/Loki ingress requires basic auth beyond the default lab setup
export GRAFANA_USERNAME=grafana-user
export GRAFANA_PASSWORD=grafana-secret
vagrant up
```

Or edit `/etc/default/jenkins` inside the VM and restart Jenkins:

```bash
vagrant ssh runner-ci
sudo nano /etc/default/jenkins
sudo systemctl restart jenkins
```

### CI Pipeline Flow

All cluster changes flow through a single path: **Jenkins builds the image → Jenkins bumps the tag in Git → Argo CD syncs the cluster**. No pipeline ever runs `kubectl apply` or `kubectl set image` directly.

```
git push → Jenkins SCM poll → docker build → docker push → kustomize edit set image → git push cluster-infra → ArgoCD sync
```

SCM polling interval: every 2 minutes for app pipelines (`my-redis`, `redis-gui-tester`), every 5 minutes for `mcp-server`.

**Note:** Jenkins only shows polling activity in the job's "SCM Polling Log" (not in the main build history) when changes are detected. You can check polling status by going to each job → "SCM Polling Log".

### Check Jenkins Status

```bash
vagrant ssh runner-ci -c "systemctl status jenkins"
```

### Re-applying Jenkins Configuration

The `cluster-infra/jenkins/` folder is synced to `/jenkins/` on the VM via **rsync**, which only runs automatically at `vagrant up` time. When iterating on `jcasc.yaml`, `plugins.txt`, or any Jenkinsfile, you must resync the folder first, then re-run the provisioner:

```bash
vagrant rsync runner-ci && vagrant provision runner-ci --provision-with jenkins
```

`setup-jenkins.sh` itself lives in `vm-setup/` which is always up-to-date on the VM via the default VirtualBox shared folder (`/vagrant`), so changes to it are reflected immediately without a resync.

Changes to **`jcasc.yaml`** or **`setup-jenkins.sh`** require the rsync + `vagrant provision runner-ci --provision-with jenkins` flow above so Jenkins reloads JCasC and systemd-injected env vars. If you only change a **Jenkinsfile** under `/jenkins/pipelines/` on the VM, rsync (or `vagrant up` resync) may be enough for the next build — the seed job reads those paths from disk; re-run the jenkins provisioner if you need plugins or JCasC updates in the same iteration.

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
vagrant rsync runner-ci && vagrant provision runner-ci --provision-with monitoring
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
vagrant rsync runner-ci && vagrant provision runner-ci --provision-with dashboard
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

| Application  | Path                 | Namespace | Sync policy          |
| ------------ | -------------------- | --------- | -------------------- |
| `namespaces` | `k8s/namespaces/`    | (various) | Auto-sync + selfHeal |
| `my-redis`   | `k8s/apps/my-redis/` | `k8s-lab` | Auto-sync + selfHeal |

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
vagrant rsync runner-ci && vagrant provision runner-ci --provision-with argocd
```

The script is idempotent (`helm upgrade --install`), so it is safe to run multiple times.

### Memory Considerations

Argo CD adds ~300–500 MB of RAM. The `k3s-master` VM has 3072 MB which is sufficient. Monitor usage with:

```bash
kubectl top pods -n argocd
```

---

## MCP Server

The runner-ci VM hosts the [Spring AI MCP server](https://github.com/nilslee/k8s-lab-mcp) which gives Cursor IDE live access to the cluster's Kubernetes API, Prometheus metrics, Loki logs, and ArgoCD state.

### How It Works

The MCP server runs as a Docker container on runner-ci. Cursor connects to it over the host-only network using the streamable HTTP transport:

```
Cursor (macOS) ──▶ http://192.168.56.10:9000/mcp ──▶ mcp-server container
                                                          ├─ Kubernetes API  192.168.56.11:6443  (via kubeconfig)
                                                          ├─ Prometheus       prometheus.k8s.lab  (via Ingress)
                                                          ├─ Loki             loki.k8s.lab        (via Ingress)
                                                          └─ ArgoCD           argocd.k8s.lab      (via Ingress)
```

### Cursor MCP Config

Add to `~/.cursor/mcp.json` on your macOS host:

```json
{
  "mcpServers": {
    "k8s-lab": {
      "url": "http://192.168.56.10:9000/mcp"
    }
  }
}
```

### Deploying / Updating via Jenkins

The MCP server is **not** started at `vagrant up` time — it is treated as a deployed application managed by the `mcp-server` Jenkins pipeline. After a fresh `vagrant up`, trigger the first deploy manually:

1. Open [http://192.168.56.10:8080](http://192.168.56.10:8080) → **mcp-server** job → **Build Now**

Subsequent updates are triggered automatically by SCM polling (every 5 minutes) when changes are made to the local `./mcp/` directory (the Jenkins pipeline copies it from `/mcp` on the VM).

The pipeline is idempotent — it stops and removes the old container before starting a new one.

### Grafana / Loki basic auth (optional)

The MCP app reads `GRAFANA_USERNAME` and `GRAFANA_PASSWORD` at container startup (see [`application.yaml` in k8s-lab-mcp](https://github.com/nilslee/k8s-lab-mcp/blob/main/src/main/resources/application.yaml)). The **`mcp-server`** pipeline binds the Jenkins credential **`mcp-grafana-loki`** and passes them into `docker run` as `-e` variables so they stay masked in the console compared to raw env echoes.

**Single path in this lab:** export `GRAFANA_USERNAME` / `GRAFANA_PASSWORD` on the host before `vagrant up` or `vagrant provision runner-ci --provision-with jenkins` → systemd exposes them to Jenkins → JCasC defines `mcp-grafana-loki` → the pipeline injects them into the container. If both are unset, the credential is empty and the MCP server still runs; it simply omits the `Authorization` header when calling Loki (fine when ingress does not require auth).

### Checking Container Status

```bash
vagrant ssh runner-ci -c "docker ps && docker logs mcp-server --tail 20"
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

- All VMs share a VirtualBox host-only network (`192.168.56.0/24`)
- The container registry is **insecure** (plain HTTP); `registries.yaml` on each k3s node tells containerd to allow it
- The runner accesses the k3s API at `https://192.168.56.11:6443` using `/vagrant/kubeconfig`
- Workflows reference the registry as `192.168.56.10:5000/<image-name>`
- MetalLB VIP pool (`192.168.56.200-220`) sits outside the static VM range (`.10-.13`) to avoid collisions
- k3s's bundled ServiceLB and Traefik are disabled (`--disable servicelb --disable traefik`) in favour of MetalLB + NGINX
