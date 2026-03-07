# Family Reunion Site Recovery

This document describes how to recover the Family Reunion site onto the `kind-reunion`
Kubernetes cluster using Velero backups stored in AWS S3 and locally via MinIO.

---

## How Recovery Works

```
  PRODUCTION CLUSTER
  ┌─────────────────────────────────────┐
  │  ArgoCD  │  Keycloak  │  Apps  ...  │
  │                                     │
  │  Velero (twice-daily backup schedule)│
  └──────────┬──────────────────────────┘
             │ writes backups
             ▼
  ┌──────────────────────────────────────────────────┐
  │               BACKUP STORAGE                     │
  │                                                  │
  │  AWS S3                      Local Filesystem    │
  │  goodman-reunion-            /home/ron-goodman/  │
  │  velero-backups/             velero-backups/     │
  │  backups/                    backups/            │
  │  (primary)                   (fallback via MinIO)│
  └──────────┬───────────────────────────────────────┘
             │ restore on demand
             ▼
  REUNION CLUSTER (this machine)
  ┌─────────────────────────────────────────────────────┐
  │  Step 1: ./installation.sh   (create kind cluster)  │
  │  Step 2: helmfile sync       (install infrastructure)│
  │  Step 3: velero restore create (restore apps)       │
  │                                                     │
  │  Infrastructure          Restored from backup       │
  │  ─────────────           ──────────────────────     │
  │  metrics-server          ArgoCD                     │
  │  Prometheus              Keycloak                   │
  │  Grafana                 Application namespaces     │
  │  Velero                                             │
  │  cert-manager                                       │
  │  Elasticsearch                                      │
  │  Kibana / Fluent Bit                                │
  └─────────────────────────────────────────────────────┘
```

---

## Prerequisites

The following must be installed on the machine before running any recovery steps:

- `docker` (running)
- `kind`
- `kubectl`
- `helm`
- `helmfile`
- `velero` CLI
- AWS CLI (`aws configure` completed with valid credentials)

Install the velero CLI if not already present:

```bash
curl -fsSL https://github.com/vmware-tanzu/velero/releases/download/v1.14.1/velero-v1.14.1-linux-amd64.tar.gz \
  | tar -xz -C /tmp && sudo mv /tmp/velero-v1.14.1-linux-amd64/velero /usr/local/bin/velero
```

Install the helm and helmfile binaries if not already present:

```bash
# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# helmfile
curl -fsSL https://github.com/helmfile/helmfile/releases/download/v0.169.2/helmfile_0.169.2_linux_amd64.tar.gz \
  | tar -xz -C /tmp && sudo mv /tmp/helmfile /usr/local/bin/helmfile
```

Verify helm-diff plugin is installed (required by helmfile):

```bash
helm plugin install https://github.com/databus23/helm-diff
```

---

## Recovery Steps

All commands are run from inside the repository directory:

```bash
cd /home/ron-goodman/Projects/kubernetes_cluster_setup
```

### Step 1 — Create the Cluster

```bash
./installation.sh --name reunion --control-planes 1 --workers 4
```

This script:
- Creates the kind cluster named `reunion`
- Configures file descriptor limits on all nodes
- Starts MinIO in Docker to serve local backup files from `/home/ron-goodman/velero-backups`

### Step 2 — Create Required Secrets

Velero needs two Kubernetes secrets that are not stored in the repository for security reasons.
These must be created before running `helmfile sync`.

**AWS S3 credentials** (primary backup storage):

```bash
kubectl create secret generic velero-aws-credentials \
  --namespace velero \
  --from-file=cloud=$HOME/.aws/credentials
```

**MinIO credentials** (local fallback backup storage):

```bash
kubectl create secret generic velero-minio-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin"
```

> Note: The velero namespace must exist before creating these secrets. If it does not exist yet,
> create it first: `kubectl create namespace velero`

### Step 3 — Install Infrastructure

```bash
helmfile sync
```

This installs all helm releases defined in `helmfile.yaml`:

| Release | Namespace | Purpose |
|---------|-----------|---------|
| metrics-server | kube-system | CPU/memory metrics for kubectl top and HPA |
| prometheus | monitoring | Metrics collection |
| grafana | monitoring | Metrics dashboards (pre-wired to Prometheus) |
| velero | velero | Backup and restore |
| cert-manager | cert-manager | TLS certificate management |
| keycloak | auth | Identity and access management |
| argocd | argocd | GitOps continuous delivery |
| elasticsearch | logging | Log storage |
| kibana | logging | Log dashboards |
| fluent-bit | logging | Log shipping from pods to Elasticsearch |

### Step 4 — Verify Backup Storage Locations

Before restoring, confirm Velero can reach both backup locations:

```bash
velero backup-location get
```

Expected output:

```
NAME      PROVIDER   BUCKET/PREFIX                          PHASE
default   aws        goodman-reunion-velero-backups/backups  Available
local     aws        backups                                 Available
```

Both must show `Available`. If `local` shows `Unavailable`, check that MinIO is running:

```bash
docker start minio-local
```

### Step 5 — List Available Backups

```bash
velero backup get
```

Backups follow the naming pattern `twice-daily-backup-YYYYMMDDHHMMSS`.
Always restore from the most recent `Completed` backup unless you need to roll back to an
earlier point in time.

### Step 6 — Run the Restore

**Restore from AWS S3 (primary):**

```bash
velero restore create --from-backup twice-daily-backup-20260306140044
```

**Restore from local MinIO (fallback — use when S3 is unavailable):**

```bash
velero restore create --from-backup twice-daily-backup-20260306140044 \
  --storage-location local
```

**Restore specific namespaces only:**

```bash
velero restore create --from-backup twice-daily-backup-20260306140044 \
  --include-namespaces argocd,auth,reunion
```

### Step 7 — Monitor the Restore

```bash
velero restore get
velero restore describe <restore-name>
```

Wait until the restore phase shows `Completed`. Some pods may take additional time to
reach `Running` state after the restore completes.

---

## Backup Storage Locations

| Name | Provider | Location | Use |
|------|----------|----------|-----|
| `default` | AWS S3 | `s3://goodman-reunion-velero-backups/backups/` | Primary |
| `local` | MinIO (Docker) | `/home/ron-goodman/velero-backups/backups/` | Fallback |

The `local` BSL is served by a MinIO Docker container (`minio-local`) that mounts the
local backup directory. The `installation.sh` script starts this container automatically.

---

## Rotating AWS Credentials

When AWS credentials are rotated, update the Kubernetes secret without touching `helmfile.yaml`:

```bash
aws configure   # enter new credentials

kubectl create secret generic velero-aws-credentials \
  --namespace velero \
  --from-file=cloud=$HOME/.aws/credentials \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## FAQ

**Q: Will the restore run automatically twice a day, or only when I decide to recover?**

The restore runs only when you manually trigger it. Nothing restores automatically.
What runs twice a day is the backup schedule on the production cluster — it creates
snapshots of the cluster state every 12 hours and writes them to S3 and the local
backup directory. The restore is always an intentional, on-demand action that you
initiate when you need to recover.

---

**Q: When I want to restore, do I set up a separate cluster?**

No. You restore into this same reunion cluster on this machine. The full recovery flow is:

1. `./installation.sh` — creates the kind cluster
2. `helmfile sync` — installs all infrastructure (Grafana, Velero, ArgoCD, etc.)
3. `velero restore create --from-backup <name>` — restores your application workloads

There is no separate cluster involved.

---

**Q: Does `helmfile sync` only install the backup/Velero part?**

No. `helmfile sync` installs everything defined in `helmfile.yaml` — metrics-server,
Prometheus, Grafana, Velero, cert-manager, Keycloak, ArgoCD, Elasticsearch, Kibana,
and Fluent Bit. Velero is just one of the releases.

The reason all infrastructure is installed first is that Velero must be running before
it can restore anything. The `velero restore` command is a separate, final step.

---

**Q: Can all three recovery commands be run from inside the repository directory?**

Yes. All three commands work from `/home/ron-goodman/Projects/kubernetes_cluster_setup/`:

- `./installation.sh` — uses the local script
- `helmfile sync` — reads `helmfile.yaml` from the current directory
- `velero restore create ...` — uses the kubectl context set by `installation.sh`

Your full disaster recovery is three commands from one directory.

---

**Q: If I run the restore right now, will it affect the production setup?**

No. The reunion cluster is completely isolated — it runs entirely inside Docker containers
on this machine and has no connection to the production environment.

The only resources shared with production are the S3 bucket and the local backup directory,
both of which are read-only during a restore. Velero never writes to or deletes from the
backup storage during a restore operation.

It is strongly recommended to do a test restore before you need it in an emergency, so
you can verify the process works and know what to expect.
