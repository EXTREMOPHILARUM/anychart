#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Check and install dependencies
check_and_install() {
    if ! command -v $1 &> /dev/null; then
        print_color $YELLOW "$1 is not installed. Installing it now..."
        bash -c "$(cat << EOF
$2
EOF
)"
    fi
}

check_and_install helm "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
check_and_install python3 "sudo apt-get update && sudo apt-get install -y python3 python3-pip"
check_and_install pip3 "sudo apt-get update && sudo apt-get install -y python3-pip"
check_and_install docker "curl -fsSL https://get.docker.com | sh"
check_and_install kind "
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/
"
check_and_install ct "
curl -LO https://github.com/helm/chart-testing/releases/download/v3.11.0/chart-testing_3.11.0_linux_amd64.tar.gz
tar -xzvf chart-testing_3.11.0_linux_amd64.tar.gz
sudo mv ct /usr/local/bin/
rm chart-testing_3.11.0_linux_amd64.tar.gz
"

pip3 install yamale yamllint

# Print environment information
print_color $YELLOW "Environment Information:"
echo "Helm version: $(helm version --short)"
echo "Python version: $(python3 --version)"
echo "chart-testing version: $(ct version)"
echo "KinD version: $(kind version)"
echo "Current directory: $(pwd)"
echo "Contents of current directory:"
ls -la

# Lint the chart
print_color $YELLOW "Linting the Helm chart..."
helm lint . || { print_color $RED "Helm lint failed."; exit 1; }
print_color $GREEN "Helm lint passed successfully."

# Run chart-testing lint
print_color $YELLOW "Running chart-testing lint..."
ct lint --config ct.yaml --charts . || {
    print_color $RED "chart-testing lint failed. Here's more detailed output:"
    ct lint --config ct.yaml --charts . --debug
    exit 1
}
print_color $GREEN "chart-testing lint passed successfully."

# Create KinD cluster
print_color $YELLOW "Creating KinD cluster..."
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
EOF

kind create cluster --name helm-test --config kind-config.yaml || {
    print_color $RED "Failed to create KinD cluster. Attempting to delete existing cluster..."
    kind delete cluster --name helm-test
    print_color $YELLOW "Retrying cluster creation..."
    kind create cluster --name helm-test --config kind-config.yaml || { 
        print_color $RED "Failed to create KinD cluster after retry. Exiting."; 
        exit 1; 
    }
}
print_color $GREEN "KinD cluster created successfully."

# Set kubectl context to the new cluster
kubectl cluster-info --context kind-helm-test

# Perform installation
print_color $YELLOW "Performing installation on the KinD cluster..."
helm install kubecanvas . || { print_color $RED "Installation failed."; kind delete cluster --name helm-test; exit 1; }
print_color $GREEN "Installation successful."

# Wait for pods to be ready
print_color $YELLOW "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubecanvas --timeout=300s || { 
    print_color $RED "Pods did not become ready in time."; 
    helm uninstall kubecanvas;
    kind delete cluster --name helm-test; 
    exit 1; 
}
print_color $GREEN "All pods are ready."

# Run tests
print_color $YELLOW "Running Helm tests..."
helm test kubecanvas || { 
    print_color $RED "Helm tests failed."; 
    helm uninstall kubecanvas;
    kind delete cluster --name helm-test; 
    exit 1; 
}
print_color $GREEN "Helm tests passed successfully."

# Clean up
print_color $YELLOW "Cleaning up..."
helm uninstall kubecanvas
kind delete cluster --name helm-test
print_color $GREEN "Cleanup completed."

print_color $GREEN "All tests passed successfully!"
