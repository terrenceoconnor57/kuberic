.PHONY: build lint yaml-validate crd-validate operator-validate apply-crd apply-operator clean kind-cluster kind-delete

IMAGE ?= kuberic-operator:dev

build:
	docker build -t $(IMAGE) -f Dockerfile .

lint:
	python3 -m pyflakes src || true

yaml-validate:
	@echo "Validating YAML syntax..."
	@python3 -c "import yaml; yaml.safe_load(open('config/crd/clusterutilization-crd.yaml'))" && echo "✓ CRD YAML is valid"
	@python3 -c "import yaml; [list(yaml.safe_load_all(open(f))) for f in ['config/operator/sa.yaml', 'config/operator/rbac.yaml', 'config/operator/deployment.yaml']]" && echo "✓ Operator manifests are valid"
	@python3 -c "import yaml; yaml.safe_load(open('config/samples/clusterutil.yaml'))" && echo "✓ Sample YAML is valid"

crd-validate:
	@kubectl version > /dev/null 2>&1 || (echo "Error: No Kubernetes cluster available. Use 'make yaml-validate' for offline validation." && exit 1)
	kubectl apply --dry-run=client -f config/crd/clusterutilization-crd.yaml

operator-validate:
	@kubectl version > /dev/null 2>&1 || (echo "Error: No Kubernetes cluster available. Use 'make yaml-validate' for offline validation." && exit 1)
	kubectl apply --dry-run=client -f config/operator/sa.yaml
	kubectl apply --dry-run=client -f config/operator/rbac.yaml
	kubectl apply --dry-run=client -f config/operator/deployment.yaml

apply-crd:
	kubectl apply -f config/crd/clusterutilization-crd.yaml

apply-operator:
	kubectl apply -f config/operator/sa.yaml
	kubectl apply -f config/operator/rbac.yaml
	kubectl apply -f config/operator/deployment.yaml

clean:
	docker rmi $(IMAGE) || true

kind-cluster:
	@which kind > /dev/null || (echo "Installing kind..." && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind)
	@kind get clusters | grep -q kuberic || kind create cluster --name kuberic
	@echo "✓ Kind cluster 'kuberic' is ready"

kind-delete:
	kind delete cluster --name kuberic

