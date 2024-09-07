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

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    print_color $RED "Helm is not installed. Please install Helm first."
    exit 1
fi

# Check if chart-testing (ct) is installed
if ! command -v ct &> /dev/null; then
    print_color $YELLOW "chart-testing (ct) is not installed. Installing it now..."
    curl -LO https://github.com/helm/chart-testing/releases/download/v3.11.0/chart-testing_3.11.0_linux_amd64.tar.gz
    tar -xzvf chart-testing_3.11.0_linux_amd64.tar.gz
    sudo mv ct /usr/local/bin/
    rm chart-testing_3.11.0_linux_amd64.tar.gz
fi

# Lint the chart
print_color $YELLOW "Linting the Helm chart..."
if helm lint .; then
    print_color $GREEN "Helm lint passed successfully."
else
    print_color $RED "Helm lint failed."
    exit 1
fi

# Run chart-testing lint
print_color $YELLOW "Running chart-testing lint..."
if ct lint --config ct.yaml; then
    print_color $GREEN "chart-testing lint passed successfully."
else
    print_color $RED "chart-testing lint failed."
    exit 1
fi

# Perform a dry-run installation
print_color $YELLOW "Performing a dry-run installation..."
if helm install --dry-run --debug kubecanvas .; then
    print_color $GREEN "Dry-run installation successful."
else
    print_color $RED "Dry-run installation failed."
    exit 1
fi

# If using Kubernetes, you can uncomment these lines to test against a real cluster
# print_color $YELLOW "Installing chart in Kubernetes cluster..."
# if helm install kubecanvas . --namespace test --create-namespace; then
#     print_color $GREEN "Chart installed successfully in the cluster."
#     helm uninstall kubecanvas --namespace test
#     kubectl delete namespace test
# else
#     print_color $RED "Chart installation in cluster failed."
#     exit 1
# fi

print_color $GREEN "All tests passed successfully!"