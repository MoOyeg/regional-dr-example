# Feature: Auto-Detect Base Domain from Route53

## Overview

The ansible-runner script now automatically detects the cluster base domain from Route53 if not explicitly provided in the cluster configuration. This uses the appropriate AWS credentials for each cluster.

## Implementation Details

### Files Modified

1. **deploy-clusters.yml** - Main deployment playbook
   - Removed `cluster_base_domain` from required variables validation
   - Added Route53 query task to fetch first hosted zone
   - Set `cluster_base_domain` from query result
   - Added failure handling if no zones found
   - Enhanced display message to show when auto-detected

2. **README.md** - Main documentation
   - Added "Auto-Detect Base Domain" to features list
   - Added new "Auto-Detecting Base Domain from Route53" section
   - Updated cluster configuration example with optional comment

3. **QUICKSTART.md** - Quick start guide
   - Added note that `cluster_base_domain` is optional

4. **inventory/host_vars/cluster[1-3]** - Example configurations
   - Updated comments to indicate auto-detection capability

5. **inventory/host_vars/cluster-auto-domain.example** - New example
   - Complete example showing usage without `cluster_base_domain`

6. **AUTO-DOMAIN-EXAMPLE.md** - New documentation
   - Comprehensive guide on auto-detection feature
   - Use cases and examples
   - Troubleshooting guide

## How It Works

### Workflow

1. Cluster configuration is loaded from `inventory/host_vars/<cluster>.yml`
2. If `cluster_base_domain` is not defined or empty:
   - Query Route53 using the credential set specified for that cluster
   - Extract first hosted zone name
   - Set `cluster_base_domain` to the zone name
   - If no zones found, fail with clear error message
3. Continue with normal deployment using the base domain

### Code Flow

```yaml
# 1. Validate credentials first
- name: Set AWS credentials based on credential set
  set_fact:
    aws_access_key: "{{ lookup('env', 'AWS_ACCESS_KEY_ID_' + (aws_credential_set | string)) }}"
    aws_secret_key: "{{ lookup('env', 'AWS_SECRET_ACCESS_KEY_' + (aws_credential_set | string)) }}"

# 2. Query Route53 if needed
- name: Get first Route53 hosted zone if cluster_base_domain not provided
  shell: |
    AWS_ACCESS_KEY_ID="{{ aws_access_key }}" \
    AWS_SECRET_ACCESS_KEY="{{ aws_secret_key }}" \
    aws route53 list-hosted-zones \
      --query 'HostedZones[0].Name' \
      --output text | sed 's/\.$//'
  when: cluster_base_domain is not defined or cluster_base_domain == ""

# 3. Set the domain
- name: Set cluster_base_domain from Route53
  set_fact:
    cluster_base_domain: "{{ route53_zone_result.stdout }}"

# 4. Fail if still not found
- name: Fail if no cluster_base_domain found
  fail:
    msg: "cluster_base_domain is not defined and no Route53 hosted zones found"
  when: cluster_base_domain is not defined or cluster_base_domain == ""
```

## Usage Examples

### Example 1: Single AWS Account with One Hosted Zone

```yaml
# inventory/host_vars/cluster-us-east-1.yml
cluster_name: "cluster-us-east-1"
# cluster_base_domain: auto-detected from Route53
aws_credential_set: 1
aws_region: "us-east-1"
# ... other config
```

### Example 2: Multiple Accounts, Different Zones

```yaml
# Credential Set 1 -> AWS Account A -> Route53: prod.example.com
# Credential Set 2 -> AWS Account B -> Route53: dev.example.com

# cluster-prod.yml
cluster_name: "cluster-prod"
aws_credential_set: 1  # Will auto-detect prod.example.com

# cluster-dev.yml
cluster_name: "cluster-dev"
aws_credential_set: 2  # Will auto-detect dev.example.com
```

### Example 3: Override Auto-Detection

```yaml
# Multiple hosted zones in account, want specific one
cluster_name: "cluster-us-east-1"
cluster_base_domain: "prod.example.com"  # Override auto-detection
aws_credential_set: 1
```

## Benefits

1. **Reduced Configuration**: No need to specify domain when you have Route53 zones
2. **Account Isolation**: Each credential set uses its own Route53 zones
3. **Flexibility**: Can still override by explicitly setting the domain
4. **Safety**: Clear error messages if auto-detection fails
5. **Multi-Account Support**: Different clusters can use different AWS accounts' zones

## Requirements

### IAM Permissions

The AWS credentials must have the following permission:

```json
{
  "Effect": "Allow",
  "Action": "route53:ListHostedZones",
  "Resource": "*"
}
```

### Route53 Setup

- At least one hosted zone must exist in the AWS account
- The hosted zone should match the domain you want to use
- If multiple zones exist, the first one (alphabetically) will be used

## Error Handling

### No Hosted Zones

```
TASK [Fail if no cluster_base_domain found] *****
fatal: [cluster-us-east-1]: FAILED! => {
    "msg": "cluster_base_domain is not defined and no Route53 hosted zones found in AWS account"
}
```

**Solution**: Create a hosted zone in Route53 or explicitly set `cluster_base_domain`

### Permission Denied

```
TASK [Get first Route53 hosted zone] *****
An error occurred (AccessDenied) when calling the ListHostedZones operation
```

**Solution**: Add `route53:ListHostedZones` permission to IAM user/role

## Testing

To test the auto-detection feature:

```bash
# Set credentials
export AWS_ACCESS_KEY_ID_1="your-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret"
export AWS_REGION_1="us-east-1"

# Create minimal cluster config without base domain
cat > inventory/host_vars/test-cluster.yml <<EOF
cluster_name: "test-cluster"
# cluster_base_domain not specified
aws_credential_set: 1
aws_region: "us-east-1"
# ... other required fields
