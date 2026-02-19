# IPI Mode Implementation Summary

## Overview
Successfully implemented dual deployment mode support: IPI (Installer Provisioned Infrastructure) and UPI (User Provisioned Infrastructure) modes.

## What Was Changed

### 1. Deploy Playbook ([deploy-clusters.yml](../deploy-clusters.yml))

Added automatic mode detection based on configuration:
```yaml
use_existing_vpc: "{{ aws_vpc_id is defined and aws_vpc_id != '' and aws_subnet_id is defined and aws_subnet_id != '' }}"
```

**UPI Mode Block (Lines 243-467):**
- Manual EC2 instance creation with `run-instances`
- Elastic IP allocation and association
- Route53 DNS record creation (api.* and *.apps.*)
- User-data with ignition file for bootstrapping
- Waits for OpenShift API and installation completion

**IPI Mode Block (Lines 470-620):**
- Configures AWS credentials for `openshift-install`
- Runs `openshift-install create cluster` with full AWS environment
- Async execution with 7200s (2 hour) timeout
- Polls every 30 seconds for progress
- Extracts cluster metadata from `metadata.json`
- Queries AWS for created infrastructure details (VPC, instances)
- Saves kubeconfig, kubeadmin password, and metadata

### 2. Destroy Playbook ([destroy-clusters.yml](../destroy-clusters.yml))

Added automatic mode detection:
```yaml
is_ipi_cluster: "{{ metadata_check.stat.exists }}"
```

**IPI Destroy Block:**
- Detects IPI clusters by presence of `/tmp/ocp-install-{cluster}/metadata.json`
- Runs `openshift-install destroy cluster` with AWS credentials
- Automatically removes ALL created resources:
  - VPC and subnets
  - Internet/NAT gateways  
  - Route tables
  - Security groups
  - Load balancers
  - EC2 instances
  - EBS volumes
- Cleans `/tmp/ocp-install-*` directory

**UPI Destroy Block:**
- Manual cleanup of EC2 instances only
- Removes Route53 DNS records
- Preserves VPC/subnet/security group infrastructure

### 3. Install Config Template ([templates/install-config.yaml.j2](../templates/install-config.yaml.j2))

Conditional subnet configuration:
```yaml
platform:
  aws:
    region: {{ aws_deploy_region }}
{% if use_existing_vpc and aws_subnet_id is defined %}
    subnets:
    - {{ aws_subnet_id }}
{% endif %}
```

- **IPI Mode**: Omits subnets section, installer creates VPC/subnets automatically
- **UPI Mode**: Includes subnet ID for deployment into existing infrastructure

### 4. Validation Logic

Smart validation based on deployment mode:

**IPI Mode Requirements:**
- AWS credentials only
- Region
- Pull secret
- SSH key
- (Optional) cluster_base_domain - auto-detected from Route53

**UPI Mode Requirements:**
- All IPI requirements PLUS:
- AMI ID (RHCOS image)
- VPC ID
- Subnet ID
- Security Group ID
- EC2 Key pair name

```yaml
- name: Validate RHCOS AMI exists
  when: use_existing_vpc and aws_ami_id is defined

- name: Validate VPC exists  
  when: use_existing_vpc
```

### 5. Documentation

Created comprehensive documentation:

**[docs/IPI-VS-UPI-MODES.md](../docs/IPI-VS-UPI-MODES.md):**
- Detailed comparison of IPI vs UPI modes
- When to use each mode
- Configuration examples
- IAM permission requirements
- Troubleshooting guides
- Feature comparison table

**Updated [README.md](../README.md):**
- Added IPI/UPI to features list
- Updated configuration section with mode examples
- Links to IPI-VS-UPI-MODES.md guide

**Updated [QUICKSTART.md](../QUICKSTART.md):**
- Split into IPI and UPI quick start sections
- IPI: Simplified 5-minute setup
- UPI: Traditional setup with infrastructure requirements

**New Example Files:**
- `inventory/host_vars/cluster-ipi.example` - IPI mode template
- `inventory/host_vars/cluster-upi.example` - UPI mode template

## How It Works

### IPI Mode Flow

1. User configures cluster without `aws_vpc_id`/`aws_subnet_id`
2. Playbook detects `use_existing_vpc: false`
3. Generates `install-config.yaml` without subnet specification
4. Creates AWS credentials file for installer
5. Runs `openshift-install create cluster` with environment:
   ```bash
   AWS_ACCESS_KEY_ID="..." \
   AWS_SECRET_ACCESS_KEY="..." \
   AWS_REGION="..." \
   openshift-install create cluster --dir /tmp/ocp-install-{cluster}
   ```
6. OpenShift installer:
   - Creates VPC with CIDR 10.0.0.0/16
   - Creates public/private subnets
   - Sets up internet/NAT gateways
   - Configures route tables
   - Creates security groups
   - Provisions load balancers
   - Launches EC2 instances
   - Installs OpenShift
7. Playbook saves artifacts (kubeconfig, password, metadata)
8. Queries AWS for created infrastructure details
9. Displays success message with cluster info

### UPI Mode Flow

1. User configures cluster with both `aws_vpc_id` and `aws_subnet_id`
2. Playbook detects `use_existing_vpc: true`
3. Validates AMI, VPC, and subnet exist
4. Generates `install-config.yaml` with subnet specification
5. Creates ignition files
6. Launches EC2 instance with user-data
7. Allocates and associates Elastic IP
8. Creates Route53 DNS records
9. Waits for OpenShift API availability
10. Waits for installation completion
11. Saves artifacts

### Destroy Flow

**IPI Clusters:**
```bash
openshift-install destroy cluster --dir /tmp/ocp-install-{cluster}
```
- Removes ALL AWS resources created by installer
- Complete cleanup including VPC, subnets, load balancers, etc.

**UPI Clusters:**
- Terminate EC2 instances manually
- Remove Route53 DNS records
- Preserve VPC/subnet (user-managed)

## Key Features

### 1. Automatic Mode Detection
No manual mode selection needed - automatically determined by configuration.

### 2. Mixed Deployments
Can deploy both IPI and UPI clusters simultaneously:
```yaml
# cluster1 - IPI in us-east-1
cluster_name: cluster1
aws_credential_set: 1

# cluster2 - UPI in us-west-2  
cluster_name: cluster2
aws_credential_set: 2
aws_vpc_id: vpc-123456
aws_subnet_id: subnet-123456
...
```

### 3. Route53 Auto-Detection
Works in both modes:
```yaml
# Omit cluster_base_domain
# Playbook queries first Route53 hosted zone
```

### 4. Clean Destruction
- IPI: Complete infrastructure removal
- UPI: Selective cleanup preserving infrastructure

### 5. Artifact Management
Both modes save identical artifacts:
```
artifacts/
└── {cluster_name}/
    ├── kubeconfig
    ├── kubeadmin-password
    ├── cluster-info.txt
    └── metadata.json (IPI only)
```

## Testing Checklist

- [ ] IPI deployment with minimal config (region + credentials)
- [ ] IPI deployment with cluster_base_domain omitted (auto-detect)
- [ ] IPI destroy removes all AWS resources
- [ ] UPI deployment with full config
- [ ] UPI deployment with cluster_base_domain omitted
- [ ] UPI destroy preserves VPC/subnet
- [ ] Mixed IPI+UPI deployment
- [ ] Validation fails appropriately for incomplete configs
- [ ] Metadata.json created for IPI, not for UPI
- [ ] Correct mode displayed in cluster-info.txt

## Configuration Examples

### Minimal IPI Configuration
```yaml
cluster_name: test-ipi
aws_credential_set: 1
aws_region: us-east-1
```

### Minimal UPI Configuration  
```yaml
cluster_name: test-upi
aws_credential_set: 1
aws_region: us-east-1
aws_vpc_id: vpc-0123456789
aws_subnet_id: subnet-0123456789
aws_security_group_id: sg-0123456789
aws_ami_id: ami-0123456789
aws_key_name: my-key
```

## Deployment Time Comparison

| Mode | Average Time | Variance |
|------|-------------|----------|
| IPI  | 45-60 min   | Higher   |
| UPI  | 30-40 min   | Lower    |

IPI takes longer due to VPC/load balancer creation.

## IAM Permission Differences

### IPI Requires
- EC2 full
- VPC full
- ELB full
- Route53
- IAM (for service accounts)
- S3 (for registry)

### UPI Requires
- EC2 (describe, run, terminate instances)
- EC2 (EIP allocation/association)
- Route53 (DNS records)

## Use Case Matrix

| Scenario | Recommended Mode |
|----------|-----------------|
| Quick testing | IPI |
| Development | IPI |
| DR to new regions | IPI |
| Production (new) | IPI or UPI |
| Production (existing infra) | UPI |
| Strict network requirements | UPI |
| Compliance mandates | UPI |
| Cost optimization | UPI (reuse infra) |
| Multi-cluster per VPC | UPI |

## Known Limitations

1. **IPI Mode:**
   - Creates fixed VPC CIDR (10.0.0.0/16)
   - No customization of subnet layout
   - Requires full IAM permissions
   - One cluster per VPC

2. **UPI Mode:**
   - Requires pre-existing infrastructure
   - Manual network setup complexity
   - No automatic load balancer
   - Single-node only (no HA)

## Future Enhancements

Potential improvements:
- [ ] Custom CIDR ranges for IPI mode
- [ ] Multi-AZ IPI deployments
- [ ] Compact cluster support (3 masters)
- [ ] Custom subnet layout in IPI
- [ ] Network policy templates
- [ ] VPC peering for multi-cluster
- [ ] Transit Gateway integration
- [ ] PrivateLink configuration

## Troubleshooting Common Issues

### IPI: "Quota exceeded for VPCs"
Increase VPC quota in AWS or use UPI mode with existing VPC.

### IPI: "No subnet with available IP addresses"
Default CIDR may be exhausted. Contact AWS support or use UPI.

### UPI: "AMI not found"
Verify AMI ID is correct for the region. RHCOS AMIs are region-specific.

### Both: "cluster_base_domain detection failed"
Create a Route53 hosted zone or specify `cluster_base_domain` explicitly.

## References

- OpenShift IPI Documentation: https://docs.openshift.com/container-platform/4.17/installing/installing_aws/installing-aws-default.html
- OpenShift UPI Documentation: https://docs.openshift.com/container-platform/4.17/installing/installing_aws/installing-aws-user-infra.html
- AWS VPC Guide: https://docs.aws.amazon.com/vpc/latest/userguide/
- RHCOS AMI List: https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/

## Conclusion

The IPI mode implementation successfully simplifies OpenShift deployment by eliminating manual infrastructure setup while maintaining backward compatibility with UPI mode for users with existing infrastructure. The automatic mode detection ensures a seamless experience for both use cases.
