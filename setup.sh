#!/bin/bash
# Quick setup script for Regional DR deployment using Podman

set -e

echo "=== Regional Disaster Recovery - Setup ==="

# Check prerequisites
echo "Checking prerequisites..."

# Check Podman
if ! command -v podman &> /dev/null; then
    echo "Error: Podman is required"
    echo "Install with:"
    echo "  RHEL/Fedora: sudo dnf install -y podman"
    echo "  Ubuntu/Debian: sudo apt install -y podman"
    exit 1
fi

echo "Podman found: $(podman --version)"

# Build Ansible container image
echo ""
echo "Building Ansible container image..."
./ansible-runner.sh build

# Check for pull secret
if [ ! -f "pull-secret.json" ]; then
    echo ""
    echo "Warning: pull-secret.json not found"
    echo "Download from: https://console.redhat.com/openshift/install/pull-secret"
    echo "Save as: pull-secret.json in this directory"
fi

# Check for SSH key
if [ ! -f "ssh-key.pub" ]; then
    echo ""
    echo "Warning: ssh-key.pub not found"
    echo "Generate with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa"
    echo "Then copy: cp ~/.ssh/id_rsa.pub ssh-key.pub"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Set AWS credentials as environment variables"
echo "2. Edit inventory/group_vars/all.yml with your configuration"
echo "3. Create host_vars files for each cluster (see inventory/host_vars/*.example)"
echo "4. Add cluster names to inventory/hosts"
echo "5. Run: ./ansible-runner.sh deploy"
echo ""
echo "Additional commands:"
echo "  ./ansible-runner.sh deploy --limit cluster1  # Deploy specific cluster"
echo "  ./ansible-runner.sh deploy -v                 # Verbose output"
echo "  ./ansible-runner.sh destroy                   # Destroy clusters"
echo "  ./ansible-runner.sh validate                  # Validate configuration"
echo "  ./ansible-runner.sh shell                     # Open Ansible container shell"
echo ""
