#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Kuberic Operator Setup Script"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${YELLOW}Step 1: Installing Python dependencies...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python3 not found. Please install Python 3.x${NC}"
    exit 1
fi

# Try different installation methods in order of preference
INSTALLED=false

# Method 1: Try venv (cleanest)
if python3 -m venv --help &> /dev/null 2>&1; then
    echo "Creating virtual environment..."
    if python3 -m venv venv 2>/dev/null; then
        source venv/bin/activate
        pip install --upgrade pip > /dev/null 2>&1
        if pip install kopf kubernetes pydantic 2>/dev/null; then
            INSTALLED=true
            echo -e "${GREEN}✓ Python dependencies installed in virtual environment${NC}"
        else
            deactivate 2>/dev/null || true
            rm -rf venv
        fi
    fi
fi

# Method 2: Try pip with --break-system-packages (for containerized environments)
if [ "$INSTALLED" = false ]; then
    echo "Installing with --break-system-packages..."
    if pip install --break-system-packages kopf kubernetes pydantic 2>/dev/null; then
        INSTALLED=true
        echo -e "${GREEN}✓ Python dependencies installed${NC}"
    elif pip3 install --break-system-packages kopf kubernetes pydantic 2>/dev/null; then
        INSTALLED=true
        echo -e "${GREEN}✓ Python dependencies installed${NC}"
    fi
fi

# Method 3: Try without any flags (might work on some systems)
if [ "$INSTALLED" = false ]; then
    echo "Trying standard pip install..."
    if pip install --user kopf kubernetes pydantic 2>/dev/null; then
        INSTALLED=true
        echo -e "${GREEN}✓ Python dependencies installed${NC}"
    elif pip3 install --user kopf kubernetes pydantic 2>/dev/null; then
        INSTALLED=true
        echo -e "${GREEN}✓ Python dependencies installed${NC}"
    fi
fi

if [ "$INSTALLED" = false ]; then
    echo -e "${RED}✗ Failed to install Python dependencies${NC}"
    echo "Please install manually:"
    echo "  pip install --break-system-packages kopf kubernetes pydantic"
    echo "or"
    echo "  python3 -m venv venv && source venv/bin/activate && pip install kopf kubernetes pydantic"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Checking Kubernetes cluster...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured and a cluster is accessible"
    exit 1
fi
echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"

echo ""
echo -e "${YELLOW}Step 3: Applying CRD...${NC}"
kubectl apply -f config/crd/clusterutilization-crd.yaml
echo -e "${GREEN}✓ CRD applied${NC}"

echo ""
echo -e "${YELLOW}Step 4: Applying RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)...${NC}"
kubectl apply -f config/operator/sa.yaml
kubectl apply -f config/operator/rbac.yaml
echo -e "${GREEN}✓ RBAC configured${NC}"

echo ""
echo -e "${YELLOW}Step 5: Installing metrics-server...${NC}"
if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    echo "Metrics-server already installed"
else
    echo "Installing metrics-server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    echo "Waiting for metrics-server deployment to be created..."
    sleep 5
    
    # Patch for environments without proper TLS (like Killercoda, kind, minikube)
    echo "Patching metrics-server for insecure TLS..."
    kubectl patch deployment metrics-server -n kube-system --type='json' \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
fi

echo "Waiting for metrics-server to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/metrics-server -n kube-system || echo "Metrics-server may take longer to start"
echo -e "${GREEN}✓ Metrics-server installed${NC}"

echo ""
echo -e "${YELLOW}Step 6: Creating sample ClusterUtilization resource...${NC}"
kubectl apply -f config/samples/clusterutil.yaml
echo -e "${GREEN}✓ ClusterUtilization resource created${NC}"

echo ""
echo -e "${YELLOW}Step 7: Creating test workloads...${NC}"
if ! kubectl get deployment nginx &> /dev/null; then
    kubectl create deployment nginx --image=nginx --replicas=3
    echo "Created nginx deployment"
fi
if ! kubectl get deployment busybox &> /dev/null; then
    kubectl create deployment busybox --image=busybox --replicas=2 -- sleep 3600
    echo "Created busybox deployment"
fi
echo -e "${GREEN}✓ Test workloads created${NC}"

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Start the operator:"
echo -e "   ${YELLOW}kopf run --verbose src/kuberic/main.py${NC}"
echo "   or if using venv:"
echo -e "   ${YELLOW}source venv/bin/activate && kopf run --verbose src/kuberic/main.py${NC}"
echo ""
echo "2. Wait 60-90 seconds for metrics to be collected"
echo ""
echo "3. Check the status:"
echo -e "   ${YELLOW}kubectl get clusterutilizations${NC}"
echo -e "   ${YELLOW}kubectl get cu -o yaml${NC}"
echo ""
echo "4. View operator logs in real-time:"
echo -e "   ${YELLOW}kubectl logs -f -l app=kuberic-operator -n kube-system${NC}"
echo "   (if running as deployment)"
echo ""
echo "5. Check metrics-server is working:"
echo -e "   ${YELLOW}kubectl top nodes${NC}"
echo -e "   ${YELLOW}kubectl top pods -A${NC}"
echo ""
echo "=========================================="
echo ""
echo -e "${YELLOW}To run operator in background:${NC}"
echo "nohup kopf run --verbose src/kuberic/main.py > operator.log 2>&1 &"
echo ""
echo -e "${YELLOW}To view operator logs:${NC}"
echo "tail -f operator.log"
echo ""

