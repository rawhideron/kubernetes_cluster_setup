# Kubernetes-in-Docker (kind) cluster setup

This repository provides a small helper to create a local Kubernetes cluster using `kind`.

Prerequisites
- `kind` installed
- `kubectl` installed and on your PATH

Create a cluster
Run the installer script which generates a kind config and creates the cluster. The script checks that a container runtime (Docker, Podman, or containerd) is running and accessible. If you see permission errors communicating with Docker, either run the command with `sudo` or add your user to the `docker` group (create it first if it doesn't exist).

```bash
./installation.sh --name my-cluster --control-planes 1 --workers 2
# or, if Docker requires root:
# sudo ./installation.sh --name my-cluster --control-planes 1 --workers 2
```

Arguments
- `--name NAME` — cluster name (defaults to `kind`)
- `--control-planes VAL` — either a number (e.g. `3`) to generate control-plane node names, or a comma-separated list of names (e.g. `cp1,cp2`). Defaults to `1`.
- `--workers VAL` — either a number or comma-separated names for worker nodes. Defaults to `0`.
- `--image IMAGE` — kind node image (default `kindest/node:v1.34.0`).

Notes
- The script prints the generated kind config file path; it's left in `/tmp` so you can inspect it.
- To delete the cluster:

```bash
kind delete cluster --name my-cluster
```

Removed helper scripts
- `ingress-nginx-setup.sh` and `metrics-server.sh` were removed from this repo to keep the cluster creation focused.

Questions or changes
- If you want separate helper scripts for optional addons (ingress, metrics), I can add them back as optional installers.
