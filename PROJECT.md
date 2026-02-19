# Regional DR Example - Project Summary

## What This Project Does

This is an Ansible-based automation tool that deploys Red Hat OpenShift (Single Node) clusters across multiple AWS regions using different AWS credentials. It's designed for disaster recovery scenarios where you need OpenShift clusters in different geographic regions or AWS accounts.

## Key Features

1. **Multi-Credential Support**: Accepts 1-3 different AWS credential sets
2. **Region Selection**: Each cluster can use a different credential set
3. **Automated Deployment**: Full OpenShift installation automation
4. **Containerized**: Runs in Podman, no local Ansible installation needed
5. **DNS Management**: Optional Route53 integration
6. **Resource Cleanup**: Automated cluster destruction

## Quick Example

```bash
# Set up 3 regions with different credentials
export AWS_ACCESS_KEY_ID_1="key-for-us-east"
export AWS_SECRET_ACCESS_KEY_1="secret-for-us-east"
export AWS_REGION_1="us-east-1"

export AWS_ACCESS_KEY_ID_2="key-for-us-west"
export AWS_SECRET_ACCESS_KEY_2="secret-for-us-west"
export AWS_REGION_2="us-west-2"

export AWS_ACCESS_KEY_ID_3="key-for-eu-west"
export AWS_SECRET_ACCESS_KEY_3="secret-for-eu-west"
export AWS_REGION_3="eu-west-1"

# Deploy clusters
./ansible-runner.sh deploy

# Result: 3 OpenShift clusters in 3 different regions
```

## Architecture

```
Control Node (Your Laptop)
         │
         ├─── Credential Set 1 ──> AWS us-east-1 ──> OpenShift Cluster
         │
         ├─── Credential Set 2 ──> AWS us-west-2 ──> OpenShift Cluster
         │
         └─── Credential Set 3 ──> AWS eu-west-1 ──> OpenShift Cluster
```

## Files Overview

### Core Scripts
- `ansible-runner.sh` - Main script (handles credentials, runs Ansible in container)
- `setup.sh` - Initial setup and container build

### Playbooks
- `deploy-clusters.yml` - Deploys OpenShift clusters
- `destroy-clusters.yml` - Destroys clusters and cleans up resources
- `validate.yml` - Validates credentials and configuration
- `list-clusters.yml` - Lists configured clusters

### Configuration
- `inventory/hosts` - List of clusters to manage
- `inventory/group_vars/all.yml` - Global defaults
- `inventory/host_vars/*.example` - Example cluster configurations
- `templates/install-config.yaml.j2` - OpenShift install-config template

### Container
- `Containerfile` - Ansible container definition (includes AWS CLI, oc, openshift-install)
- `ansible.cfg` - Ansible configuration

### Documentation
- `README.md` - Full documentation
- `QUICKSTART.md` - Quick start guide
- `CREDENTIALS.md` - Multi-credential management guide
- `.gitignore` - Excludes sensitive files

## How It Works

1. **Credential Management**: 
   - Reads AWS_ACCESS_KEY_ID_1, AWS_SECRET_ACCESS_KEY_1, AWS_REGION_1 (and _2, _3)
   - Each cluster specifies which credential set to use

2. **Deployment Process**:
   - Validates AWS credentials and resources
   - Generates OpenShift install-config.yaml
   - Creates ignition files
   - Launches EC2 instance with ignition as user-data
   - Allocates and associates Elastic IP
   - Creates Route53 DNS records (optional)
   - Waits for OpenShift installation to complete
   - Extracts and saves credentials

3. **Resource Tagging**:
   - All resources tagged with cluster name
   - Easy identification and cost tracking

## Use Cases

### Use Case 1: True Regional DR
Deploy OpenShift in geographically diverse regions for disaster recovery:
- Primary: us-east-1
- DR: us-west-2
- Backup DR: eu-west-1

### Use Case 2: Multi-Account
Deploy across different AWS accounts:
- Production account → us-east-1
- Staging account → us-west-2
- Development account → us-east-2

### Use Case 3: Customer-Specific
Different credentials for different customers/projects:
- Customer A → us-east-1 (credential set 1)
- Customer B → us-west-2 (credential set 2)
- Internal → eu-west-1 (credential set 3)

## Inspiration

Based on the approach from [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery) by Moyo Oyegunle, but focused on:
- Multi-credential support (1-3 AWS credential sets)
- AWS-only deployments
- Regional disaster recovery
- Simplified credential management

## What's Created Per Cluster

- 1 × EC2 instance (default: m5.2xlarge)
- 1 × EBS volume (default: 120GB gp3)
- 1 × Elastic IP
- 2 × Route53 DNS records (if enabled):
  - api.cluster-name.domain
  - *.apps.cluster-name.domain

## Requirements

- Podman (or Docker)
- Red Hat pull secret
- SSH key pair
- AWS credentials (1-3 sets)
- AWS VPC, subnet, security group per region
- EC2 key pair per region
- RHCOS AMI ID per region

## Cost Estimate

Per cluster (24/7):
- m5.2xlarge: ~$280/month
- 120GB EBS: ~$12/month
- Elastic IP: $0 (when associated)
- **Total**: ~$295/month

## Getting Started

See [QUICKSTART.md](QUICKSTART.md) for step-by-step setup guide.

## Advanced Topics

- [Multi-Credential Management](CREDENTIALS.md)
- [Full Documentation](README.md)

## Future Enhancements

- ACM (Advanced Cluster Management) integration
- VolSync for application-level replication
- Submariner for cross-cluster networking
- Automated failover testing
- Application deployment templates

## Support

This is an example project for demonstration purposes. For production use:
- Review and adjust for your security requirements
- Test thoroughly in non-production environments
- Follow your organization's AWS and OpenShift best practices
- Consult Red Hat OpenShift documentation

## License

Provided as-is for educational and operational purposes.
