# Migration Guide: UPI ↔ IPI Mode

## Overview

This guide helps you understand how to work with both deployment modes and when you might want to change approaches.

## Understanding the Modes

### IPI (Installer Provisioned Infrastructure)
- OpenShift installer creates ALL AWS infrastructure
- Automatic VPC, subnets, load balancers, security groups
- Simpler configuration
- Complete cleanup on destroy

### UPI (User Provisioned Infrastructure)  
- You provide existing VPC/subnet/security infrastructure
- Manual control over network topology
- More complex configuration
- Preserves infrastructure on cluster destroy

## Configuration Differences

### IPI Mode Configuration
```yaml
# Minimal - just region and credentials
cluster_name: my-cluster
aws_region: us-east-1
aws_credential_set: 1
```

### UPI Mode Configuration
```yaml
# Full infrastructure details required
cluster_name: my-cluster
aws_region: us-east-1
aws_credential_set: 1

# UPI-specific fields
aws_vpc_id: vpc-0123456789abcdef0
aws_subnet_id: subnet-0123456789abcdef0
aws_security_group_id: sg-0123456789abcdef0
aws_ami_id: ami-0123456789abcdef0
aws_key_name: my-keypair
```

## Switching Modes

### From UPI to IPI

**When to switch:**
- Want simplified management
- Don't need existing infrastructure
- Want automatic cleanup
- Moving to new AWS account/region

**Steps:**
1. Remove UPI-specific fields from configuration:
   ```yaml
   # Delete these lines:
   # aws_vpc_id: vpc-...
   # aws_subnet_id: subnet-...
   # aws_security_group_id: sg-...
   # aws_ami_id: ami-...
   # aws_key_name: ...
   ```

2. Deploy new cluster:
   ```bash
   ./ansible-runner.sh deploy --limit my-cluster
   ```

3. OpenShift installer creates new infrastructure automatically

**Migration workflow for existing workloads:**
```bash
# 1. Deploy new IPI cluster
./ansible-runner.sh deploy --limit new-ipi-cluster

# 2. Wait for deployment
# Typically 45-60 minutes

# 3. Migrate workloads
export KUBECONFIG_OLD=artifacts/old-upi-cluster/kubeconfig
export KUBECONFIG_NEW=artifacts/new-ipi-cluster/kubeconfig

# 4. Backup old cluster
oc --kubeconfig=$KUBECONFIG_OLD get all --all-namespaces -o yaml > backup.yaml

# 5. Restore to new cluster
oc --kubeconfig=$KUBECONFIG_NEW apply -f backup.yaml

# 6. Update DNS (if not using Route53 auto-management)
# Point your applications to new cluster

# 7. Verify workloads
oc --kubeconfig=$KUBECONFIG_NEW get pods --all-namespaces

# 8. Destroy old cluster
./ansible-runner.sh destroy --limit old-upi-cluster
```

### From IPI to UPI

**When to switch:**
- Need specific network topology
- Want to share VPC with other resources
- Compliance requirements
- Cost optimization through infrastructure reuse

**Steps:**

1. **Identify existing infrastructure to use:**
   ```bash
   # List VPCs
   aws ec2 describe-vpcs --region us-east-1
   
   # List subnets
   aws ec2 describe-subnets --region us-east-1 \
     --filters "Name=vpc-id,Values=vpc-0123456789"
   
   # List security groups
   aws ec2 describe-security-groups --region us-east-1 \
     --filters "Name=vpc-id,Values=vpc-0123456789"
   ```

2. **Get RHCOS AMI for region:**
   ```bash
   aws ec2 describe-images \
     --owners 309956199498 \
     --region us-east-1 \
     --filters "Name=name,Values=rhcos-4.17*" \
     --query 'Images[0].ImageId' \
     --output text
   ```

3. **Create EC2 key pair:**
   ```bash
   aws ec2 create-key-pair \
     --key-name my-openshift-key \
     --region us-east-1 \
     --query 'KeyMaterial' \
     --output text > my-openshift-key.pem
   chmod 400 my-openshift-key.pem
   ```

4. **Update cluster configuration:**
   ```yaml
   cluster_name: my-cluster
   aws_region: us-east-1
   aws_credential_set: 1
   
   # Add UPI fields
   aws_vpc_id: vpc-0123456789abcdef0
   aws_subnet_id: subnet-0123456789abcdef0
   aws_security_group_id: sg-0123456789abcdef0
   aws_ami_id: ami-0123456789abcdef0
   aws_key_name: my-openshift-key
   ```

5. **Deploy:**
   ```bash
   ./ansible-runner.sh deploy --limit my-cluster
   ```

## Mixed Mode Deployments

You can deploy clusters in different modes simultaneously:

```yaml
# inventory/host_vars/cluster-prod-upi.yml
cluster_name: cluster-prod-upi
aws_credential_set: 1
aws_vpc_id: vpc-existing
aws_subnet_id: subnet-existing
aws_security_group_id: sg-existing
aws_ami_id: ami-rhcos
aws_key_name: prod-key

# inventory/host_vars/cluster-dr-ipi.yml  
cluster_name: cluster-dr-ipi
aws_credential_set: 2
# No infrastructure fields - IPI mode!
```

Deploy both:
```bash
./ansible-runner.sh deploy
```

## Cost Comparison

### IPI Mode Costs

**Per Cluster:**
- VPC: Free (within limits)
- NAT Gateway: ~$32/month
- Network Load Balancer: ~$16/month
- EC2 instance (m5.2xlarge): ~$277/month
- EBS storage (120GB): ~$12/month
- Total: **~$337/month**

### UPI Mode Costs (Shared VPC)

**Per Cluster:**
- VPC: Shared (amortized)
- NAT Gateway: Shared (amortized)
- No Load Balancer: $0
- EC2 instance (m5.2xlarge): ~$277/month
- EBS storage (120GB): ~$12/month
- Elastic IP: ~$3.60/month
- Total: **~$293/month**

**Multiple clusters in UPI:**
- First cluster: $337/month (creates infra)
- Additional clusters: $293/month each (reuse infra)
- 3 clusters: $923/month vs $1,011/month IPI (save ~$88/month)

## Use Case Decision Tree

```
Need OpenShift cluster?
├─ New AWS account/region?
│  └─ IPI (simpler)
│
├─ Existing VPC you must use?
│  └─ UPI (required)
│
├─ Multiple clusters planned?
│  ├─ In same VPC? → UPI (cost savings)
│  └─ In different VPCs? → IPI (simpler)
│
├─ Strict network requirements?
│  └─ UPI (more control)
│
├─ Testing/Development?
│  └─ IPI (faster setup)
│
└─ Production?
   ├─ New deployment? → IPI or UPI (your choice)
   └─ Existing infra? → UPI (reuse resources)
```

## Cluster Destroy Behavior

### IPI Destroy
```bash
./ansible-runner.sh destroy --limit my-ipi-cluster
```
**Removes:**
- ✅ VPC and subnets
- ✅ Internet Gateway
- ✅ NAT Gateway
- ✅ Route Tables
- ✅ Security Groups
- ✅ Load Balancers
- ✅ EC2 instances
- ✅ EBS volumes
- ✅ Route53 records (if created)

**Result:** Complete cleanup, nothing left in AWS

### UPI Destroy
```bash
./ansible-runner.sh destroy --limit my-upi-cluster
```
**Removes:**
- ✅ EC2 instance
- ✅ Elastic IP
- ✅ Route53 records (if created)

**Preserves:**
- ⚠️ VPC
- ⚠️ Subnet
- ⚠️ Security Group
- ⚠️ Internet Gateway
- ⚠️ Key Pair

**Result:** Cluster removed, infrastructure remains for reuse

## Network Topology Comparison

### IPI Network Layout
```
VPC (10.0.0.0/16)
├── Public Subnet 1 (10.0.0.0/20) - AZ-a
├── Public Subnet 2 (10.0.16.0/20) - AZ-b
├── Public Subnet 3 (10.0.32.0/20) - AZ-c
├── Private Subnet 1 (10.0.128.0/20) - AZ-a
├── Private Subnet 2 (10.0.144.0/20) - AZ-b
├── Private Subnet 3 (10.0.160.0/20) - AZ-c
├── Internet Gateway
├── NAT Gateway (in public subnets)
├── Network Load Balancer (public)
└── Network Load Balancer (internal)
```

### UPI Network Layout (Single Node)
```
Your Existing VPC
├── Your Subnet (any CIDR)
├── Your Internet Gateway
├── Single EC2 Instance
│   ├── Public IP (Elastic)
│   └── Private IP
└── Your Security Group
    ├── Ingress: 22, 80, 443, 6443
    └── Egress: All
```

## Security Group Requirements

### IPI Mode
Security groups created automatically with proper rules.

### UPI Mode
Required inbound rules:
```
Port    Protocol    Source          Purpose
22      TCP         Your IP         SSH access
80      TCP         0.0.0.0/0       HTTP ingress
443     TCP         0.0.0.0/0       HTTPS ingress
6443    TCP         0.0.0.0/0       Kubernetes API
```

Required outbound rules:
```
Port    Protocol    Destination     Purpose
All     All         0.0.0.0/0       Internet access
```

## Backup and Disaster Recovery

### IPI to IPI (Different Region)
```bash
# 1. Deploy DR cluster in different region
cp inventory/host_vars/prod-ipi.yml \
   inventory/host_vars/dr-ipi.yml

# Edit DR cluster config
vim inventory/host_vars/dr-ipi.yml
# Change: cluster_name, aws_region, aws_credential_set

# Deploy DR cluster
./ansible-runner.sh deploy --limit dr-ipi

# 2. Setup replication (Velero, ACM, etc.)
```

### UPI to UPI (Same VPC)
```bash
# Deploy second cluster in same VPC
cp inventory/host_vars/prod-upi.yml \
   inventory/host_vars/dr-upi.yml

# Edit: cluster_name (different subnet in same VPC)
vim inventory/host_vars/dr-upi.yml

./ansible-runner.sh deploy --limit dr-upi
```

### IPI to UPI (DR Strategy)
```bash
# Production: IPI (easy management)
# DR: UPI (cost-effective, manual control)

# Deploy both
./ansible-runner.sh deploy
```

## Troubleshooting Mode-Specific Issues

### IPI Issues

**"VPC limit exceeded"**
```bash
# Check current VPCs
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[*].[VpcId,CidrBlock]'

# Request limit increase or use UPI
```

**"Subnet CIDR conflicts"**
```bash
# IPI uses 10.0.0.0/16 by default
# Check existing VPC CIDRs
aws ec2 describe-vpcs --query 'Vpcs[*].CidrBlock'

# If conflict, use UPI mode with different CIDR
```

**"EIP allocation failed"**
```bash
# Check EIP quota
aws ec2 describe-addresses --region us-east-1

# Request quota increase
```

### UPI Issues

**"AMI not found"**
```bash
# AMIs are region-specific
# Get correct AMI for your region
aws ec2 describe-images --owners 309956199498 \
  --region YOUR_REGION \
  --filters "Name=name,Values=rhcos-4.17*" \
  --query 'Images[0].[ImageId,Name]'
```

**"Subnet has no internet access"**
```bash
# Verify internet gateway
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=YOUR_VPC_ID"

# Verify route table
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=YOUR_VPC_ID" \
  --query 'RouteTables[*].Routes[*].[DestinationCidrBlock,GatewayId]'
```

## Best Practices

### IPI Best Practices
1. ✅ Use for testing and development
2. ✅ Use for DR clusters in new regions
3. ✅ Let installer manage everything
4. ✅ Monitor AWS service limits
5. ✅ Use destroy when done (complete cleanup)

### UPI Best Practices
1. ✅ Document your infrastructure
2. ✅ Use consistent naming conventions
3. ✅ Tag resources for tracking
4. ✅ Share VPC for multiple clusters
5. ✅ Keep security groups minimal
6. ✅ Backup VPC configuration

### Mixed Mode Best Practices
1. ✅ Production (UPI) + DR (IPI)
2. ✅ Consistent cluster naming
3. ✅ Document mode per cluster
4. ✅ Use cluster labels/tags
5. ✅ Separate credential sets per environment

## Summary

| Aspect | IPI Mode | UPI Mode |
|--------|----------|----------|
| **Setup Complexity** | Low | Medium-High |
| **Configuration Lines** | 3-4 | 8-10 |
| **Deployment Time** | 45-60 min | 30-40 min |
| **AWS Permissions** | Extensive | Minimal |
| **Cost (single)** | Higher | Lower |
| **Cost (multiple)** | Higher | Much lower |
| **Cleanup** | Complete | Partial |
| **Network Control** | Limited | Full |
| **Best For** | Dev/Test/DR | Production |
| **Learning Curve** | Easy | Moderate |

Choose IPI for simplicity, UPI for control and cost efficiency at scale.
