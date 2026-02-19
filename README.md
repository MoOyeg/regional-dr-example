# Regional Disaster Recovery - Multi-Credential OpenShift Deployment

An Ansible automation tool for deploying OpenShift clusters across multiple AWS regions using different AWS credentials. Inspired by [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery), this tool enables true regional disaster recovery by supporting up to 3 different AWS credential sets.

## Features

- **Multi-Credential Support**: Deploy clusters using 1-3 different AWS credential sets
- **Regional Deployment**: Deploy OpenShift clusters across different AWS regions
- **Dual Deployment Modes**:
  - **IPI Mode**: OpenShift installer creates VPC, subnets, and all infrastructure automatically
  - **UPI Mode**: Deploy into existing VPC/subnet with manual infrastructure control
- **Containerized Ansible**: No local Ansible installation required - runs in Podman container
- **Single Node OpenShift**: Optimized for SNO deployments
- **Automated DNS**: Optional Route53 integration for automatic DNS configuration
- **Auto-Detect Base Domain**: Automatically fetches first Route53 hosted zone if not specified
- **Elastic IP Management**: Automatic allocation and association of Elastic IPs (UPI mode)
- **Credential Isolation**: Each cluster can use a different AWS credential set

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Control Node (Local)                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Ansible in Podman Container             │   │
│  │  - AWS Credential Set 1 (us-east-1)                 │   │
│  │  - AWS Credential Set 2 (us-west-2)                 │   │
│  │  - AWS Credential Set 3 (eu-west-1)                 │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
  ┌──────────┐      ┌──────────┐      ┌──────────┐
  │ AWS      │      │ AWS      │      │ AWS      │
  │ US-East-1│      │ US-West-2│      │ EU-West-1│
  │ (Cred 1) │      │ (Cred 2) │      │ (Cred 3) │
  │          │      │          │      │          │
  │ OpenShift│      │ OpenShift│      │ OpenShift│
  │ Cluster  │      │ Cluster  │      │ Cluster  │
  └──────────┘      └──────────┘      └──────────┘
```

## Prerequisites

### Local Requirements

1. **Podman** (or Docker)
   ```bash
   # RHEL/Fedora
   sudo dnf install -y podman
   
   # Ubuntu/Debian
   sudo apt install -y podman
   ```

2. **Red Hat Pull Secret**
   - Download from: https://console.redhat.com/openshift/install/pull-secret
   - Save as `pull-secret.json` in project directory

3. **SSH Key Pair**
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   cp ~/.ssh/id_rsa.pub ./ssh-key.pub
   ```

### AWS Requirements

For each region you want to deploy to, you'll need:

1. **AWS Credentials** with appropriate permissions
2. **VPC** with internet connectivity
3. **Subnet** in the VPC
4. **Security Group** allowing:
   - Port 6443 (API)
   - Port 22 (SSH)
   - Port 80 (HTTP)
   - Port 443 (HTTPS)
   - Port 22623 (Machine Config)
5. **EC2 Key Pair** created in the region
6. **RHCOS AMI ID** for your region and OpenShift version
7. **Route53 Hosted Zone** (optional, for automatic DNS)

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:CreateVolume",
        "ec2:AttachVolume",
        "ec2:DescribeVolumes",
        "ec2:CreateTags",
        "ec2:AllocateAddress",
        "ec2:AssociateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:DescribeImages",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd regional-dr-example
./setup.sh
```

### 2. Configure AWS Credentials

Set up credentials for 1-3 AWS regions:

```bash
# Primary region (us-east-1)
export AWS_ACCESS_KEY_ID_1="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY_1="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION_1="us-east-1"

# Secondary region (us-west-2) - Optional
export AWS_ACCESS_KEY_ID_2="AKIAIOSFODNN7EXAMPLE2"
export AWS_SECRET_ACCESS_KEY_2="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY2"
export AWS_REGION_2="us-west-2"

# Tertiary region (eu-west-1) - Optional
export AWS_ACCESS_KEY_ID_3="AKIAIOSFODNN7EXAMPLE3"
export AWS_SECRET_ACCESS_KEY_3="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY3"
export AWS_REGION_3="eu-west-1"
```

### 3. Configure Clusters

Create configuration files for each cluster. Choose between IPI or UPI deployment mode:

**IPI Mode (Simple - OpenShift creates infrastructure):**
```yaml
# inventory/host_vars/cluster1.yml
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
# cluster_base_domain: example.com  # Optional - auto-detected from Route53

# That's it! OpenShift installer will create VPC, subnets, etc.
```

**UPI Mode (Advanced - Use existing infrastructure):**
```yaml
# inventory/host_vars/cluster1.yml
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
# cluster_base_domain: example.com  # Optional - auto-detected from Route53

# UPI-specific: existing infrastructure
aws_vpc_id: vpc-0123456789abcdef0
aws_subnet_id: subnet-0123456789abcdef0
aws_security_group_id: sg-0123456789abcdef0
aws_ami_id: ami-0123456789abcdef0
aws_key_name: my-keypair
```

See [IPI vs UPI Modes Guide](docs/IPI-VS-UPI-MODES.md) for detailed comparison.

```bash
# Copy example configurations
cp inventory/host_vars/cluster-us-east-1.example inventory/host_vars/cluster-us-east-1.yml
cp inventory/host_vars/cluster-us-west-2.example inventory/host_vars/cluster-us-west-2.yml

# Edit each file with your configuration
vim inventory/host_vars/cluster-us-east-1.yml
vim inventory/host_vars/cluster-us-west-2.yml
```

Add clusters to inventory:

```bash
cat >> inventory/hosts <<EOF
cluster-us-east-1
cluster-us-west-2
EOF
```

### 4. Validate Configuration

```bash
./ansible-runner.sh validate
```

### 5. Deploy Clusters

```bash
# Deploy all clusters
./ansible-runner.sh deploy

# Deploy specific cluster
./ansible-runner.sh deploy --limit cluster-us-east-1

# Deploy with verbose output
./ansible-runner.sh deploy -v
```

### 6. Access Your Clusters

After deployment (approximately 45-60 minutes per cluster):

```bash
# View cluster information
cat artifacts/cluster-us-east-1/cluster-info.txt

# Use kubeconfig
export KUBECONFIG=$(pwd)/artifacts/cluster-us-east-1/kubeconfig
oc get nodes
oc get co

# Get console password
cat artifacts/cluster-us-east-1/kubeadmin-password
```

## Project Structure

```
.
├── ansible-runner.sh                    # Main script with multi-credential support
├── setup.sh                             # Initial setup script
├── Containerfile                        # Ansible container definition
├── ansible.cfg                          # Ansible configuration
├── deploy-clusters.yml                  # Cluster deployment playbook
├── destroy-clusters.yml                 # Cluster cleanup playbook
├── validate.yml                         # Configuration validation playbook
├── list-clusters.yml                    # List configured clusters
├── inventory/
│   ├── hosts                           # Inventory file
│   ├── group_vars/
│   │   └── all.yml                     # Global variables
│   └── host_vars/
│       ├── cluster-us-east-1.example   # Example: US East 1
│       ├── cluster-us-west-2.example   # Example: US West 2
│       └── cluster-eu-west-1.example   # Example: EU West 1
├── templates/
│   └── install-config.yaml.j2          # OpenShift install config template
├── artifacts/                           # Generated cluster credentials (gitignored)
│   └── <cluster-name>/
│       ├── kubeconfig
│       ├── kubeadmin-password
│       ├── cluster-info.txt
│       └── instance-id.txt
└── README.md
```

## Usage Examples

### Deploy Multiple Clusters

```bash
# Deploy all configured clusters
./ansible-runner.sh deploy

# Watch progress in another terminal
watch -n 10 'ls -la artifacts/'
```

### Deploy to Specific Region

```bash
# Deploy only US East cluster
./ansible-runner.sh deploy --limit cluster-us-east-1

# Deploy only US West cluster
./ansible-runner.sh deploy --limit cluster-us-west-2
```

### List Configured Clusters

```bash
./ansible-runner.sh list
```

### Destroy Clusters

```bash
# Destroy all clusters (with confirmation skip)
./ansible-runner.sh destroy --yes

# Destroy specific cluster
./ansible-runner.sh destroy --limit cluster-us-east-1 --yes
```

### Debug Mode

```bash
# Open shell in Ansible container
./ansible-runner.sh shell

# Inside container, you can run AWS CLI commands
aws sts get-caller-identity --region us-east-1
aws ec2 describe-instances --region us-east-1
```

## Configuration Guide

### Cluster Configuration File

Each cluster needs a configuration file in `inventory/host_vars/<cluster-name>.yml`:

```yaml
# Cluster identification
cluster_name: "cluster-us-east-1"
cluster_base_domain: "example.com"  # Optional: auto-detected from Route53 if not provided

# AWS Credential Set to use (1, 2, or 3)
aws_credential_set: 1

# AWS Configuration
aws_region: "us-east-1"
aws_availability_zone: "us-east-1a"
aws_instance_type: "m5.2xlarge"
aws_root_volume_size: 120

# RHCOS AMI
aws_ami_id: "ami-0abcdef1234567890"

# Network Configuration
aws_vpc_id: "vpc-xxxxxxxxxxxxxxxxx"
aws_subnet_id: "subnet-xxxxxxxxxxxxxxxxx"
aws_security_group_id: "sg-xxxxxxxxxxxxxxxxx"

# SSH Key
aws_key_name: "my-keypair"

# Elastic IP
aws_create_eip: true

# Optional: Route53 DNS
aws_route53_zone: "example.com"

# OpenShift version
openshift_version: "4.17"
```

### Finding RHCOS AMI IDs

1. Visit: https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/
2. Navigate to your OpenShift version (e.g., `4.17/`)
3. Look for `rhcos-aws.json` or check AWS EC2 console under "Public images"
4. Search for: "Red Hat CoreOS" + your OpenShift version

Example AMI IDs for OpenShift 4.17:
- us-east-1: `ami-0abcdef1234567890`
- us-west-2: `ami-0fedcba9876543210`
- eu-west-1: `ami-0123456789abcdef0`

## Advanced Features

### Auto-Detecting Base Domain from Route53

If you don't specify `cluster_base_domain`, the script will automatically query Route53 using the appropriate AWS credentials and use the first hosted zone it finds:

```yaml
# Minimal configuration - base domain auto-detected
cluster_name: "cluster-us-east-1"
# cluster_base_domain will be auto-detected from Route53
aws_credential_set: 1
aws_region: "us-east-1"
# ... other required fields
```

The script will:
1. Use the AWS credentials for the specified credential set
2. Query Route53 for hosted zones
3. Use the first hosted zone as the base domain
4. Fail with a clear message if no hosted zones are found

### Using Different Instance Types

Modify `aws_instance_type` in your cluster configuration:

```yaml
# For production workloads
aws_instance_type: "m5.4xlarge"

# For development/testing
aws_instance_type: "m5.2xlarge"

# For high-performance workloads
aws_instance_type: "m5.8xlarge"
```

### Custom Root Volume Size

```yaml
# Default is 120GB
aws_root_volume_size: 120

# For larger workloads
aws_root_volume_size: 250
```

### Without Route53

If you don't have a Route53 hosted zone, you can use the Elastic IP directly:

```yaml
# Remove or comment out this line
# aws_route53_zone: "example.com"

# Access cluster via IP
# API: https://<elastic-ip>:6443
# Console: https://<elastic-ip>:8443
```

## Troubleshooting

### Check AWS Credentials

```bash
# Validate credentials
./ansible-runner.sh validate

# Or manually check
./ansible-runner.sh shell
aws sts get-caller-identity --region us-east-1
```

### Monitor EC2 Instance

```bash
# Get instance ID
cat artifacts/cluster-us-east-1/instance-id.txt

# Check instance status
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].State.Name'

# Get console output
aws ec2 get-console-output \
  --instance-id <instance-id> \
  --region us-east-1
```

### Installation Logs

```bash
# Installation logs are in temporary directory
tail -f /tmp/ocp-install-<cluster-name>/.openshift_install.log
```

### Common Issues

1. **AMI not found**: Verify AMI ID is correct for your region
2. **VPC/Subnet errors**: Ensure VPC has internet gateway and subnet has route to it
3. **Security group issues**: Verify security group allows required ports
4. **Key pair not found**: Ensure EC2 key pair exists in the target region
5. **Insufficient permissions**: Review IAM permissions above
6. **Route53 errors**: Verify hosted zone exists and matches base domain

## Cost Estimation

Running 24/7 (per cluster):
- **m5.2xlarge instance**: ~$280/month
- **EBS volumes (120GB gp3)**: ~$12/month
- **Elastic IP**: $0 (when associated)
- **Route53**: ~$0.50/month (per hosted zone)
- **Total per cluster**: ~$295/month

**Cost Saving Tips**:
- Stop instances when not in use
- Use smaller instance types for dev/test
- Delete clusters when not needed

## Security Considerations

1. **Never commit credentials**: All credential files are in `.gitignore`
2. **Use separate AWS accounts**: Consider different accounts for different regions
3. **Rotate credentials regularly**: Change AWS access keys periodically
4. **Use IAM roles when possible**: For production, use IAM roles instead of access keys
5. **Restrict security groups**: Only allow necessary ports and IPs
6. **Enable CloudTrail**: Monitor API activity for security
7. **Use VPC Flow Logs**: Monitor network traffic

## Comparison with sno-disaster-recovery

This project is inspired by [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery) but focuses on:

| Feature | sno-disaster-recovery | regional-dr-example |
|---------|----------------------|---------------------|
| Platform | OpenShift Virtualization + AWS | AWS only |
| Credentials | Single AWS credential | 1-3 AWS credentials |
| Primary Use Case | DR within datacenter | Regional DR across AWS |
| ACM Integration | Yes | Not yet |
| Application DR | VolSync | Not yet |
| Submariner | Yes | Not yet |

## Roadmap

Future enhancements:
- [ ] ACM (Advanced Cluster Management) integration
- [ ] VolSync for application-level DR
- [ ] Submariner for cluster networking
- [ ] Automated failover testing
- [ ] Cost tracking and reporting
- [ ] Support for additional cloud providers
- [ ] Application deployment templates
- [ ] Backup and restore procedures

## Support and Contributions

For issues, questions, or contributions:
- Review the OpenShift documentation: https://docs.openshift.com
- Check AWS OpenShift documentation
- Review example configurations in `inventory/host_vars/`

## License

This automation is provided as-is for educational and operational purposes.

## Acknowledgments

Inspired by [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery) by Moyo Oyegunle.
