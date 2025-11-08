# Kuberic

A Kubernetes operator for monitoring cluster resource utilization with advanced metrics and percentile tracking.

## Features

- 📊 Real-time CPU and memory utilization tracking
- 📈 Percentile metrics (p50, p90, p95) for trend analysis
- 🔝 Top namespace resource consumption tracking
- ⚠️ Automatic threshold-based recommendations
- 🚦 Pod saturation monitoring (pending/unschedulable pods)
- 📝 Historical metric buffering for accurate percentiles

## Quick Start

**One-command setup:**

```bash
./setup.sh
```

Then start the operator:

```bash
kopf run --verbose src/kuberic/main.py
```

For detailed instructions, see [QUICKSTART.md](QUICKSTART.md)

## Architecture

- **Language**: Python 3.12+
- **Framework**: Kopf (Kubernetes Operator Pythonic Framework)
- **CRD**: `ClusterUtilization` (monitoring.kuberic.io/v1)
- **Metrics Source**: Kubernetes metrics-server

## Installation

### Prerequisites

- Kubernetes cluster (1.19+)
- kubectl configured
- Python 3.8+
- metrics-server installed

### Automated Setup

```bash
git clone <your-repo-url>
cd kuberic
./setup.sh
```

### Manual Setup

```bash
# 1. Install dependencies
pip install kopf kubernetes pydantic

# 2. Apply CRD
kubectl apply -f config/crd/clusterutilization-crd.yaml

# 3. Apply RBAC
kubectl apply -f config/operator/sa.yaml
kubectl apply -f config/operator/rbac.yaml

# 4. Create a ClusterUtilization resource
kubectl apply -f config/samples/clusterutil.yaml

# 5. Run the operator
kopf run --verbose src/kuberic/main.py
```

## Configuration

Create a `ClusterUtilization` resource:

```yaml
apiVersion: monitoring.kuberic.io/v1
kind: ClusterUtilization
metadata:
  name: cluster
spec:
  scrapeIntervalSeconds: 60  # Metrics collection interval
  thresholds:
    cpu: 80                  # CPU warning threshold (%)
    memory: 85               # Memory warning threshold (%)
```

## Viewing Metrics

```bash
# List resources
kubectl get clusterutilizations
kubectl get cu  # shorthand

# View detailed status
kubectl get cu -o yaml

# Pretty print status
kubectl get cu -o jsonpath='{.items[0].status}' | python3 -m json.tool
```

## Example Output

```json
{
  "summary": {
    "cpuPercent": 3.8,
    "memoryPercent": 22.1
  },
  "percentiles": {
    "cpu": {"p50": 3.77, "p90": 5.05, "p95": 5.05},
    "memory": {"p50": 22.05, "p90": 22.47, "p95": 22.47}
  },
  "topNamespaces": [
    {"namespace": "kube-system", "cpuMillicores": 75}
  ],
  "saturation": {
    "pendingPods": 0,
    "unschedulablePods": 0
  },
  "timestamp": "2025-11-08T22:48:48.730056+00:00",
  "recommendations": []
}
```

## Development

### Dev Container

Open in VS Code with Dev Containers extension. The container includes:
- Python 3.12
- Docker CLI (for building images)
- kubectl
- All dependencies pre-installed

```bash
# Validate manifests
make yaml-validate

# Run linter
make lint

# Build operator image
make build

# Deploy to cluster
make apply-crd
make apply-operator
```

### Testing Locally

```bash
# Create a local kind cluster
make kind-cluster

# Build and load image
make build
kind load docker-image kuberic-operator:dev --name kuberic

# Deploy
make apply-crd
make apply-operator

# Clean up
make kind-delete
```

## Available Make Targets

```bash
make build              # Build Docker image
make lint               # Run Python linting
make yaml-validate      # Validate YAML syntax (no cluster needed)
make crd-validate       # Validate CRD against cluster
make operator-validate  # Validate operator manifests
make apply-crd          # Apply CRD to cluster
make apply-operator     # Deploy operator to cluster
make kind-cluster       # Create local kind cluster
make kind-delete        # Delete local kind cluster
make clean              # Remove Docker image
```

## Deployment Options

### Option 1: Run Directly (Development)
```bash
kopf run --verbose src/kuberic/main.py
```

### Option 2: Kubernetes Deployment
```bash
make build
kubectl apply -f config/operator/deployment.yaml
```

### Option 3: Background Process
```bash
nohup kopf run --verbose src/kuberic/main.py > operator.log 2>&1 &
```

## Troubleshooting

See [QUICKSTART.md](QUICKSTART.md#troubleshooting) for common issues and solutions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Your License Here]
