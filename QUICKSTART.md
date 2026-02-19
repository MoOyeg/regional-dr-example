# Quick Start Guide

Get from zero to running OpenShift clusters in different AWS regions in under 10 minutes of setup time (plus deployment time).

## Choose Your Deployment Mode

This guide supports two modes:
- **IPI Mode (Recommended for beginners)**: OpenShift creates all infrastructure automatically
- **UPI Mode (Advanced)**: Use existing VPC/subnet infrastructure

See [IPI vs UPI Comparison](docs/IPI-VS-UPI-MODES.md) for detailed differences.

## IPI Mode Quick Start (Simplest)

### Prerequisites Checklist

- [ ] Podman installed
- [ ] Red Hat pull secret downloaded  
- [ ] SSH key generated
- [ ] AWS credentials for 1-3 regions

That's it! No VPC/subnet setup required.

### 5-Minute IPI Setup

#### 1. Clone and Setup

```bash
git clone <repository-url>
cd regional-dr-example
./setup.sh
```

#### 2. Set AWS Credentials

```bash
# Region 1 (required)
export AWS_ACCESS_KEY_ID_1="your-access-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret-key"
export AWS_REGION_1="us-east-1"

# Region 2 (optional)
export AWS_ACCESS_KEY_ID_2="your-access-key"
export AWS_SECRET_ACCESS_KEY_2="your-secret-key"
export AWS_REGION_2="us-west-2"
```

#### 3. Configure First Cluster (IPI Mode)

```bash
cp inventory/host_vars/cluster-ipi.example \
   inventory/host_vars/cluster-ipi-1.yml

# Minimal configuration needed!
cat > inventory/host_vars/cluster-ipi-1.yml <<EOF
cluster_name: cluster-ipi-1
aws_region: us-east-1
aws_credential_set: 1
# cluster_base_domain auto-detected from Route53!
EOF
```

#### 4. Add to Inventory

```bash
echo "cluster-ipi-1" >> inventory/hosts
```

#### 5. Deploy

```bash
./ansible-runner.sh deploy
```


---

## UPI Mode Quick Start (Advanced)

### Prerequisites Checklist

- [ ] Podman installed
- [ ] Red Hat pull secret downloaded
- [ ] SSH key generated
- [ ] AWS credentials for 1-3 regions
- [ ] AWS VPC, subnet, security group created in each region
- [ ] EC2 key pair created in each region
- [ ] RHCOS AMI IDs identified for each region

### 5-Minute UPI Setup

#### 1. Clone and Setup

```bash
git clone <repository-url>
cd regional-dr-example
./setup.sh
```

#### 2. Set AWS Credentials

```bash
# Region 1 (required)
export AWS_ACCESS_KEY_ID_1="your-access-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret-key"
export AWS_REGION_1="us-east-1"

# Region 2 (optional)
export AWS_ACCESS_KEY_ID_2="your-access-key"
export AWS_SECRET_ACCESS_KEY_2="your-secret-key"
export AWS_REGION_2="us-west-2"
```

#### 3. Configure First Cluster (UPI Mode)

```bash
cp inventory/host_vars/cluster-upi.example \
   inventory/host_vars/cluster-us-east-1.yml

# Edit with your AWS resources
vim inventory/host_vars/cluster-us-east-1.yml
```

Update these values:
- `aws_ami_id`: Your RHCOS AMI
- `aws_vpc_id`: Your VPC ID
- `aws_subnet_id`: Your subnet ID
- `aws_security_group_id`: Your security group ID
- `aws_key_name`: Your EC2 key pair name

**Note**: `cluster_base_domain` is optional. If not provided, it will be auto-detected from your first Route53 hosted zone.

#### 4. Add to Inventory

```bash
echo "cluster-us-east-1" >> inventory/hosts
```

#### 5. Validate

```bash
./ansible-runner.sh validate
```

#### 6. Deploy

```bash
./ansible-runner.sh deploy
```

---

## Monitor Progress

In another terminal:

```bash
# Watch for credentials
watch -n 10 'ls -la artifacts/'

# Check AWS
aws ec2 describe-instances \
  --filters "Name=tag:cluster,Values=cluster-us-east-1" \
  --region us-east-1
```

## Access Cluster

After 45-60 minutes:

```bash
# Export kubeconfig
export KUBECONFIG=$(pwd)/artifacts/cluster-us-east-1/kubeconfig

# Check cluster
oc get nodes
oc get co

# Get password
cat artifacts/cluster-us-east-1/kubeadmin-password

# Console URL
cat artifacts/cluster-us-east-1/cluster-info.txt
```

## Next Steps

### Deploy Second Cluster

```bash
# Configure second cluster
cp inventory/host_vars/cluster-us-west-2.example \
   inventory/host_vars/cluster-us-west-2.yml

vim inventory/host_vars/cluster-us-west-2.yml

# Add to inventory
echo "cluster-us-west-2" >> inventory/hosts

# Deploy
./ansible-runner.sh deploy --limit cluster-us-west-2
```

### Deploy Third Cluster

```bash
# Set third credential set
export AWS_ACCESS_KEY_ID_3="your-access-key"
export AWS_SECRET_ACCESS_KEY_3="your-secret-key"
export AWS_REGION_3="eu-west-1"

# Configure
cp inventory/host_vars/cluster-eu-west-1.example \
   inventory/host_vars/cluster-eu-west-1.yml

vim inventory/host_vars/cluster-eu-west-1.yml

# Add to inventory
echo "cluster-eu-west-1" >> inventory/hosts

# Deploy
./ansible-runner.sh deploy --limit cluster-eu-west-1
```

## Common Commands

```bash
# List configured clusters
./ansible-runner.sh list

# Deploy all clusters
./ansible-runner.sh deploy

# Deploy specific cluster
./ansible-runner.sh deploy --limit cluster-us-east-1

# Destroy cluster
./ansible-runner.sh destroy --limit cluster-us-east-1

# Validate configuration
./ansible-runner.sh validate

# Open debug shell
./ansible-runner.sh shell
```

## Troubleshooting

### Credentials Not Working

```bash
./ansible-runner.sh shell
aws sts get-caller-identity --region us-east-1
```

### Can't Find AMI

Visit: https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.17/

### Instance Not Starting

```bash
# Check instance
aws ec2 describe-instances \
  --filters "Name=tag:cluster,Values=cluster-us-east-1" \
  --region us-east-1

# Get console output
aws ec2 get-console-output \
  --instance-id <instance-id> \
  --region us-east-1
```

### Installation Hanging

```bash
# Check installation logs
tail -f /tmp/ocp-install-cluster-us-east-1/.openshift_install.log
```

## What Gets Created

For each cluster:
- 1 EC2 instance (m5.2xlarge by default)
- 1 EBS root volume (120GB gp3)
- 1 Elastic IP
- 2 Route53 records (if configured):
  - api.<cluster>.<domain>
  - *.apps.<cluster>.<domain>

## Cost Per Cluster

- Instance: ~$280/month
- Storage: ~$12/month
- Elastic IP: $0 (when associated)
- **Total**: ~$295/month

## Clean Up

```bash
# Destroy specific cluster
./ansible-runner.sh destroy --limit cluster-us-east-1

# Destroy all clusters
./ansible-runner.sh destroy
```

Artifacts are preserved in `artifacts/` directory.
