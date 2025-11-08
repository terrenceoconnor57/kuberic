# kuberic

Kubernetes utilization operator.

## Build

```bash
make build
```

## Deploy

```bash
kubectl apply -f config/crd/clusterutilization-crd.yaml
kubectl apply -f config/operator/sa.yaml
kubectl apply -f config/operator/rbac.yaml
kubectl apply -f config/operator/deployment.yaml
kubectl apply -f config/samples/clusterutil.yaml
```

## Check

```bash
kubectl get clusterutilizations
kubectl get clusterutilizations cluster -o yaml
```

## Dev

Open in VS Code with Dev Containers extension. Container mounts host Docker socket.

```bash
make lint
make crd-validate
```
