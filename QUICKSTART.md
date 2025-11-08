# Kuberic Operator - Quick Start Guide

This guide will help you get the Kuberic operator running in any Kubernetes environment.

## Prerequisites

- Kubernetes cluster (kind, minikube, GKE, EKS, AKS, or playground like Killercoda)
- kubectl configured and connected
- Python 3.8+
- Git (to clone the repository)

## One-Command Setup

```bash
git clone <your-repo-url>
cd kuberic
./setup.sh
```

The script will:
1. ✅ Install Python dependencies (kopf, kubernetes, pydantic)
2. ✅ Verify Kubernetes cluster connection
3. ✅ Apply the ClusterUtilization CRD
4. ✅ Create RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
5. ✅ Install metrics-server
6. ✅ Create a sample ClusterUtilization resource
7. ✅ Deploy test workloads (nginx, busybox)

## Running the Operator

### Option 1: Run Directly (Development)

```bash
# If you used venv
source venv/bin/activate

# Start the operator
kopf run --verbose src/kuberic/main.py
```

### Option 2: Run in Background

```bash
nohup kopf run --verbose src/kuberic/main.py > operator.log 2>&1 &

# View logs
tail -f operator.log
```

### Option 3: Deploy as Kubernetes Deployment

```bash
# Build the image
make build

# For kind clusters, load the image
kind load docker-image kuberic-operator:dev --name kuberic

# Deploy
kubectl apply -f config/operator/deployment.yaml

# View logs
kubectl logs -f -n kube-system -l app=kuberic-operator
```

## Verify It's Working

### 1. Check the ClusterUtilization Resource

Wait 60-90 seconds for the first metrics collection cycle, then:

```bash
# List resources
kubectl get clusterutilizations
# or shorthand:
kubectl get cu

# View detailed status
kubectl get cu -o yaml

# Pretty print the status
kubectl get cu -o jsonpath='{.items[0].status}' | python3 -m json.tool
```

### 2. Expected Output

You should see metrics like:

```json
{
  "summary": {
    "cpuPercent": 3.8,
    "memoryPercent": 22.1
  },
  "percentiles": {
    "cpu": {
      "p50": 3.77,
      "p90": 5.05,
      "p95": 5.05
    },
    "memory": {
      "p50": 22.05,
      "p90": 22.47,
      "p95": 22.47
    }
  },
  "topNamespaces": [
    {
      "namespace": "kube-system",
      "cpuMillicores": 75
    }
  ],
  "saturation": {
    "pendingPods": 0,
    "unschedulablePods": 0
  },
  "timestamp": "2025-11-08T22:48:48.730056+00:00",
  "recommendations": []
}
```

### 3. Check Operator Logs

Look for log lines like:

```
[INFO] kuberic: cpu=3.8% p90=5.1% mem=22.2% pods=18
[INFO] Timer 'scrape_metrics' succeeded.
```

### 4. Verify Metrics Server

```bash
# Check if metrics are available
kubectl top nodes
kubectl top pods -A
```

## Troubleshooting

### Operator Not Updating Status

1. **Check RBAC permissions:**
   ```bash
   kubectl auth can-i patch clusterutilizations --as=system:serviceaccount:kube-system:kuberic-operator
   kubectl auth can-i update clusterutilizations/status --as=system:serviceaccount:kube-system:kuberic-operator
   ```
   Both should return "yes"

2. **Check operator logs for errors:**
   ```bash
   kubectl logs -n kube-system -l app=kuberic-operator --tail=50
   ```

3. **Check events:**
   ```bash
   kubectl get events --sort-by='.lastTimestamp' | grep cluster
   ```

### Metrics Server Not Working

```bash
# Check metrics-server status
kubectl get deployment metrics-server -n kube-system

# Check metrics-server logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# For local clusters (kind, minikube, etc.), ensure insecure TLS is enabled:
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### Python Dependencies Issues

```bash
# Use virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate
pip install kopf kubernetes pydantic

# Or use --break-system-packages (for containerized environments)
pip install --break-system-packages kopf kubernetes pydantic
```

## Configuration

Edit the sample ClusterUtilization resource to change settings:

```yaml
apiVersion: monitoring.kuberic.io/v1
kind: ClusterUtilization
metadata:
  name: cluster
spec:
  scrapeIntervalSeconds: 60  # How often to collect metrics
  thresholds:
    cpu: 80      # CPU threshold for recommendations
    memory: 85   # Memory threshold for recommendations
```

Apply changes:

```bash
kubectl apply -f config/samples/clusterutil.yaml
```

## Testing in Different Environments

### Killercoda / Play with Kubernetes
```bash
git clone <your-repo>
cd kuberic
./setup.sh
kopf run --verbose src/kuberic/main.py
```

### Local Kind Cluster
```bash
kind create cluster --name kuberic
./setup.sh
make build
kind load docker-image kuberic-operator:dev --name kuberic
kubectl apply -f config/operator/deployment.yaml
```

### Cloud Providers (GKE, EKS, AKS)
```bash
# Connect to your cluster
gcloud container clusters get-credentials <cluster-name>  # GKE
# or
aws eks update-kubeconfig --name <cluster-name>  # EKS
# or
az aks get-credentials --resource-group <rg> --name <cluster-name>  # AKS

# Run setup
./setup.sh

# Deploy operator
make build
docker push <your-registry>/kuberic-operator:dev
kubectl apply -f config/operator/deployment.yaml
```

## Development Commands

```bash
# Validate YAML files
make yaml-validate

# Validate against cluster
make crd-validate
make operator-validate

# Build Docker image
make build

# Apply everything
make apply-crd
make apply-operator

# Clean up
kubectl delete -f config/samples/clusterutil.yaml
kubectl delete -f config/operator/deployment.yaml
kubectl delete -f config/operator/rbac.yaml
kubectl delete -f config/operator/sa.yaml
kubectl delete -f config/crd/clusterutilization-crd.yaml
```

## Next Steps

- Customize thresholds and scrape intervals
- Add more ClusterUtilization resources for different monitoring profiles
- Integrate with your alerting system
- Deploy to production clusters

## Support

For issues, check the operator logs and Kubernetes events. The operator provides detailed logging at INFO level by default.

