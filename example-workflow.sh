#!/bin/bash
# Example workflow for deploying 3 OpenShift clusters in different regions
# This is a demonstration script - modify for your actual credentials and resources

set -e

echo "=== Regional DR Deployment Workflow Example ==="
echo ""
echo "This script demonstrates deploying 3 OpenShift clusters"
echo "across 3 AWS regions using different credential sets."
echo ""

# Step 1: Set AWS Credentials
echo "Step 1: Setting AWS Credentials"
echo "================================"

# Region 1: US East (Primary)
export AWS_ACCESS_KEY_ID_1="AKIAIOSFODNN7EXAMPLE1"
export AWS_SECRET_ACCESS_KEY_1="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY1"
export AWS_REGION_1="us-east-1"

# Region 2: US West (DR)
export AWS_ACCESS_KEY_ID_2="AKIAIOSFODNN7EXAMPLE2"
export AWS_SECRET_ACCESS_KEY_2="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY2"
export AWS_REGION_2="us-west-2"

# Region 3: EU West (Backup DR)
export AWS_ACCESS_KEY_ID_3="AKIAIOSFODNN7EXAMPLE3"
export AWS_SECRET_ACCESS_KEY_3="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY3"
export AWS_REGION_3="eu-west-1"

echo "✓ Credentials configured for 3 regions"
echo ""

# Step 2: Validate Setup
echo "Step 2: Validating Configuration"
echo "================================"
./ansible-runner.sh validate
echo ""

# Step 3: Configure Clusters
echo "Step 3: Cluster Configuration"
echo "=============================="
echo "Creating cluster configurations..."

# Cluster 1: US East (Primary)
cat > inventory/host_vars/cluster-us-east-1.yml <<EOF
---
cluster_name: "ocp-us-east-1"
cluster_base_domain: "example.com"
aws_credential_set: 1
aws_region: "us-east-1"
aws_availability_zone: "us-east-1a"
aws_instance_type: "m5.2xlarge"
aws_root_volume_size: 120
aws_ami_id: "ami-0abcdef1234567890"
aws_vpc_id: "vpc-xxxxxxxxxxxxxxxxx"
aws_subnet_id: "subnet-xxxxxxxxxxxxxxxxx"
aws_security_group_id: "sg-xxxxxxxxxxxxxxxxx"
aws_key_name: "my-keypair"
aws_create_eip: true
aws_route53_zone: "example.com"
openshift_version: "4.17"
EOF

# Cluster 2: US West (DR)
cat > inventory/host_vars/cluster-us-west-2.yml <<EOF
---
cluster_name: "ocp-us-west-2"
cluster_base_domain: "example.com"
aws_credential_set: 2
aws_region: "us-west-2"
aws_availability_zone: "us-west-2a"
aws_instance_type: "m5.2xlarge"
aws_root_volume_size: 120
aws_ami_id: "ami-0fedcba9876543210"
aws_vpc_id: "vpc-yyyyyyyyyyyyyyyyy"
aws_subnet_id: "subnet-yyyyyyyyyyyyyyyyy"
aws_security_group_id: "sg-yyyyyyyyyyyyyyyyy"
aws_key_name: "my-keypair"
aws_create_eip: true
aws_route53_zone: "example.com"
openshift_version: "4.17"
EOF

# Cluster 3: EU West (Backup DR)
cat > inventory/host_vars/cluster-eu-west-1.yml <<EOF
---
cluster_name: "ocp-eu-west-1"
cluster_base_domain: "example.com"
aws_credential_set: 3
aws_region: "eu-west-1"
aws_availability_zone: "eu-west-1a"
aws_instance_type: "m5.2xlarge"
aws_root_volume_size: 120
aws_ami_id: "ami-0123456789abcdef0"
aws_vpc_id: "vpc-zzzzzzzzzzzzzzzzz"
aws_subnet_id: "subnet-zzzzzzzzzzzzzzzzz"
aws_security_group_id: "sg-zzzzzzzzzzzzzzzzz"
aws_key_name: "my-keypair"
aws_create_eip: true
aws_route53_zone: "example.com"
openshift_version: "4.17"
EOF

# Update inventory
cat > inventory/hosts <<EOF
[openshift_clusters]
cluster-us-east-1
cluster-us-west-2
cluster-eu-west-1
EOF

echo "✓ Created 3 cluster configurations"
echo ""

# Step 4: List Clusters
echo "Step 4: Listing Configured Clusters"
echo "===================================="
./ansible-runner.sh list
echo ""

# Step 5: Deploy Clusters
echo "Step 5: Deploying Clusters"
echo "=========================="
echo ""
echo "This will deploy 3 OpenShift clusters:"
echo "  - ocp-us-east-1 (Primary)"
echo "  - ocp-us-west-2 (DR)"
echo "  - ocp-eu-west-1 (Backup DR)"
echo ""
echo "Deployment will take approximately 45-60 minutes per cluster."
echo ""
read -p "Press Enter to start deployment or Ctrl+C to cancel..."

# Deploy all clusters
./ansible-runner.sh deploy

echo ""
echo "Step 6: Deployment Complete!"
echo "============================"
echo ""
echo "Clusters deployed:"
echo ""
echo "1. US East (Primary):"
echo "   export KUBECONFIG=$(pwd)/artifacts/ocp-us-east-1/kubeconfig"
echo "   Console: https://console-openshift-console.apps.ocp-us-east-1.example.com"
echo ""
echo "2. US West (DR):"
echo "   export KUBECONFIG=$(pwd)/artifacts/ocp-us-west-2/kubeconfig"
echo "   Console: https://console-openshift-console.apps.ocp-us-west-2.example.com"
echo ""
echo "3. EU West (Backup DR):"
echo "   export KUBECONFIG=$(pwd)/artifacts/ocp-eu-west-1/kubeconfig"
echo "   Console: https://console-openshift-console.apps.ocp-eu-west-1.example.com"
echo ""
echo "Credentials are in artifacts/<cluster-name>/ directories"
echo ""
echo "=== Regional DR Deployment Complete! ==="
