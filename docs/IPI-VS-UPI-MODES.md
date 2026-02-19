# IPI vs UPI Deployment Modes

## Overview

This ansible-runner supports two OpenShift deployment modes:

### IPI Mode (Installer Provisioned Infrastructure)
**Use when:** You want OpenShift to automatically create all AWS infrastructure

**What it creates automatically:**
- VPC and subnets
- Internet Gateway
- NAT Gateway(s)
- Route Tables
- Security Groups
- Load Balancers
- EC2 instances
- EBS volumes

**Required configuration:**
```yaml
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
# cluster_base_domain is optional - auto-detected from Route53
# No vpc_id or subnet_id needed!
```

**When to use IPI:**
- New AWS accounts without existing infrastructure
- Testing/development environments
- Simplified deployment without manual network setup
- Multi-region DR where some regions have no infrastructure

### UPI Mode (User Provisioned Infrastructure)
**Use when:** You have existing VPC/subnet/security infrastructure

**What you provide:**
- VPC ID
- Subnet ID
- Security Group ID
- AMI ID (RHCOS image)
- SSH key name

**Required configuration:**
```yaml
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
aws_vpc_id: vpc-0123456789abcdef0
aws_subnet_id: subnet-0123456789abcdef0
aws_security_group_id: sg-0123456789abcdef0
aws_ami_id: ami-0123456789abcdef0
aws_key_name: my-keypair
# cluster_base_domain is optional - auto-detected from Route53
```

**When to use UPI:**
- Existing AWS infrastructure
- Strict network requirements
- Production environments with pre-configured networking
- Compliance requirements for specific network configurations

## How Deployment Mode is Determined

The playbook automatically detects the mode based on your configuration:

```yaml
# This logic runs automatically:
use_existing_vpc: "{{ aws_vpc_id is defined and aws_vpc_id != '' and aws_subnet_id is defined and aws_subnet_id != '' }}"
```

**If both `aws_vpc_id` AND `aws_subnet_id` are provided:** UPI Mode
**If either is missing:** IPI Mode

## Examples

### IPI Mode Example
```yaml
# inventory/host_vars/cluster1
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
cluster_base_domain: example.com  # or omit for auto-detection
```

Deploy:
```bash
./ansible-runner.sh deploy --limit cluster1
```

### UPI Mode Example
```yaml
# inventory/host_vars/cluster1
cluster_name: cluster1
aws_region: us-east-1
aws_credential_set: 1
cluster_base_domain: example.com  # or omit for auto-detection

# UPI-specific settings
aws_vpc_id: vpc-0a1b2c3d4e5f
aws_subnet_id: subnet-0a1b2c3d4e5f
aws_security_group_id: sg-0a1b2c3d4e5f
aws_ami_id: ami-0a1b2c3d4e5f
aws_key_name: my-openshift-key
```

Deploy:
```bash
./ansible-runner.sh deploy --limit cluster1
```

## Cluster Destruction

Both modes are automatically detected during destruction:

**IPI Mode:** Uses `openshift-install destroy cluster` which automatically removes all created AWS resources

**UPI Mode:** Manually terminates EC2 instances and removes DNS records (VPC/subnet/security groups are preserved)

```bash
./ansible-runner.sh destroy --limit cluster1
```

## Mixed Mode Deployments

You can deploy clusters in different modes simultaneously:

```yaml
# cluster1 - IPI mode (no VPC specified)
cluster_name: cluster1
aws_credential_set: 1

# cluster2 - UPI mode (existing VPC)
cluster_name: cluster2
aws_credential_set: 2
aws_vpc_id: vpc-existing123
aws_subnet_id: subnet-existing123
aws_security_group_id: sg-existing123
aws_ami_id: ami-rhcos456
aws_key_name: keypair1

# cluster3 - IPI mode in different region
cluster_name: cluster3
aws_credential_set: 3
```

Deploy all:
```bash
./ansible-runner.sh deploy
```

## Verification

After deployment, check the cluster-info.txt file:

```bash
cat artifacts/cluster1/cluster-info.txt
```

Look for the "Deployment Mode" line:
- **IPI:** Shows "IPI (Infrastructure created by OpenShift installer)" and lists created VPC
- **UPI:** Shows instance ID, Elastic IP, and manual infrastructure details

## Troubleshooting

### IPI Mode Issues
- Check AWS account limits (VPCs, Elastic IPs, NAT Gateways)
- Ensure IAM credentials have sufficient permissions (VPC, EC2, ELB, Route53)
- Review `/tmp/ocp-install-<cluster>/.openshift_install.log`

### UPI Mode Issues
- Verify VPC/subnet/security group exist in the specified region
- Ensure AMI ID is a valid RHCOS image for the region
- Check security group allows inbound 6443 (API) and 22 (SSH)
- Verify SSH key exists in AWS EC2 key pairs

## Best Practices

1. **Use IPI for DR scenarios** where you need rapid deployment in new regions
2. **Use UPI for production** where network topology is strictly controlled
3. **Auto-detect base domain** in both modes by omitting cluster_base_domain
4. **Save artifacts** - both modes save kubeconfig and credentials to `artifacts/`
5. **Test IPI first** - it's simpler and faster for proof-of-concept

## Credential Requirements

### IPI Mode Required Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:*",
      "elasticloadbalancing:*",
      "iam:*",
      "route53:*",
      "s3:*"
    ],
    "Resource": "*"
  }]
}
```

### UPI Mode Required Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:DescribeAddresses",
      "route53:*"
    ],
    "Resource": "*"
  }]
}
```

## Summary

| Feature | IPI Mode | UPI Mode |
|---------|----------|----------|
| VPC Creation | ✅ Automatic | ❌ Must exist |
| Subnet Creation | ✅ Automatic | ❌ Must exist |
| Security Groups | ✅ Automatic | ❌ Must exist |
| Load Balancers | ✅ Automatic | ❌ Manual/Not used |
| AMI Selection | ✅ Automatic | ❌ Must specify |
| Deployment Time | ~45-60 min | ~30-40 min |
| Destroy Cleanup | ✅ Complete | ⚠️ Keeps VPC/subnet |
| Complexity | 🟢 Low | 🟡 Medium |
| Best For | Dev/Test/DR | Production |
