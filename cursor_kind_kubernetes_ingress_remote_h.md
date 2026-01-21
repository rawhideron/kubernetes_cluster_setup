# Kind Kubernetes ingress remote host access
_Exported on 1/21/2026 at 09:43:27 EST from Cursor (2.3.41)_

---

**User**

I'm using kind to create a kubernetes infrastructure. I want to be able to use ingress to access services from a remote host. Since I'm running kubernetes within docker, there is a different way of accessing kubernetes from a remote host. How can I do this?

---

**Cursor**

When you run Kubernetes in Docker with kind, the cluster lives behind the Docker network. A remote host can’t hit Service IPs or Pod IPs directly, so you must publish ports from the Docker node to the host and then use the host’s IP. The typical approach is to run an Ingress controller inside the cluster and map host ports 80/443 to the kind control-plane node.

Here’s a concise, working pattern:

### 1) Create the kind cluster with published ports
Create a `kind-config.yaml` and expose 80/443 from the control-plane container. The example below creates one control-plane and **six worker nodes**:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        listenAddress: "0.0.0.0"
        protocol: TCP
  - role: worker
  - role: worker
  - role: worker
  - role: worker
  - role: worker
  - role: worker
```

Then create the cluster:

```
kind create cluster --config kind-config.yaml
```

### Note about `kubeadm-config.yaml`
The `kubeadm-config.yaml` file in this repo is **for kubeadm-based clusters**, not kind. Kind ignores kubeadm config files, so there is no step needed for it in this kind-based ingress flow. If you later switch to kubeadm, you would apply that file during `kubeadm init --config kubeadm-config.yaml`.

### 2) Install ingress-nginx for kind
Use the official kind deployment (it configures NodePorts and works with the port mapping):

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

### 2b) Pin ingress-nginx to the control-plane node
Because the host ports (80/443) are mapped only on the **control-plane** container, the ingress controller must run there. Patch the deployment so it schedules on the control-plane:

```
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type='merge' -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","node-role.kubernetes.io/control-plane":""}}}}}'
```

### 3) Create your Ingress resources as usual
Expose services through Ingress (e.g., `web`, `catalogue`, etc.). Make sure your Ingress has a `host` or use a catch‑all.

### 4) Access from a remote host
From another machine, hit the Docker host’s IP on port 80/443:

```
http://<docker-host-ip>/
```

If you use hostnames in the Ingress rules, add a DNS entry or `/etc/hosts` on the remote machine:

```
<docker-host-ip>  robotshop.local
```

### Alternative (if you can’t bind 80/443)
You can map a high port instead:

```yaml
- containerPort: 80
  hostPort: 8080
```

Then hit `http://<docker-host-ip>:8080`.

---

This is the cleanest way to make kind-based ingress reachable from outside the Docker host without extra VPNs or proxies. If you want, I can help wire your existing manifests in this repo to the kind ingress flow.

---

**User**

How can I remove the cluster I currently have

---

**Cursor**

To remove your current kind cluster, run:

```
kind delete cluster
```

If you created it with a custom name:

```
kind delete cluster --name <cluster-name>
```

If you’re not sure of the name, this lists them:

```
kind get clusters
```

