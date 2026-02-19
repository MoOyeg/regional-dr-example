# Multi-Credential AWS Management Guide

This guide explains how to use multiple AWS credential sets to deploy OpenShift clusters across different regions or AWS accounts.

## Credential Management System

The ansible-runner script supports up to 3 different AWS credential sets, allowing you to:
- Deploy clusters in different AWS regions with region-specific credentials
- Deploy clusters across different AWS accounts
- Isolate credentials for security and cost tracking
- Support organizational boundaries (dev/staging/prod in different accounts)

## How It Works

### Environment Variables

Each credential set uses numbered environment variables:

```bash
# Credential Set 1
export AWS_ACCESS_KEY_ID_1="AKIAIOSFODNN7EXAMPLE1"
export AWS_SECRET_ACCESS_KEY_1="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY1"
export AWS_REGION_1="us-east-1"

# Credential Set 2
export AWS_ACCESS_KEY_ID_2="AKIAIOSFODNN7EXAMPLE2"
export AWS_SECRET_ACCESS_KEY_2="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY2"
export AWS_REGION_2="us-west-2"

# Credential Set 3
export AWS_ACCESS_KEY_ID_3="AKIAIOSFODNN7EXAMPLE3"
export AWS_SECRET_ACCESS_KEY_3="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY3"
export AWS_REGION_3="eu-west-1"
```

### Cluster Configuration

Each cluster specifies which credential set to use:

```yaml
# inventory/host_vars/cluster-us-east-1.yml
cluster_name: "cluster-us-east-1"
aws_credential_set: 1  # Uses AWS_ACCESS_KEY_ID_1, etc.
aws_region: "us-east-1"
```

```yaml
# inventory/host_vars/cluster-us-west-2.yml
cluster_name: "cluster-us-west-2"
aws_credential_set: 2  # Uses AWS_ACCESS_KEY_ID_2, etc.
aws_region: "us-west-2"
```

## Use Cases

### Use Case 1: Multi-Region Deployment (Same Account)

Deploy clusters in multiple AWS regions using the same AWS account but region-specific access patterns:

```bash
# Set up credentials for different regions
export AWS_ACCESS_KEY_ID_1="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY_1="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION_1="us-east-1"

export AWS_ACCESS_KEY_ID_2="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY_2="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION_2="us-west-2"

export AWS_ACCESS_KEY_ID_3="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY_3="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION_3="eu-west-1"
```

Configure clusters:
- `cluster-us-east-1`: credential_set=1, region=us-east-1
- `cluster-us-west-2`: credential_set=2, region=us-west-2
- `cluster-eu-west-1`: credential_set=3, region=eu-west-1

### Use Case 2: Multi-Account Deployment

Deploy clusters across different AWS accounts for organizational separation:

```bash
# Production account (us-east-1)
export AWS_ACCESS_KEY_ID_1="PROD_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY_1="PROD_SECRET_KEY"
export AWS_REGION_1="us-east-1"

# Staging account (us-west-2)
export AWS_ACCESS_KEY_ID_2="STAGING_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY_2="STAGING_SECRET_KEY"
export AWS_REGION_2="us-west-2"

# Development account (us-east-2)
export AWS_ACCESS_KEY_ID_3="DEV_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY_3="DEV_SECRET_KEY"
export AWS_REGION_3="us-east-2"
```

Configure clusters:
- `cluster-production`: credential_set=1, account=production
- `cluster-staging`: credential_set=2, account=staging
- `cluster-development`: credential_set=3, account=development

### Use Case 3: DR with Primary and Secondary Regions

Primary cluster in one region, DR cluster in another:

```bash
# Primary region
export AWS_ACCESS_KEY_ID_1="PRIMARY_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY_1="PRIMARY_SECRET_KEY"
export AWS_REGION_1="us-east-1"

# DR region
export AWS_ACCESS_KEY_ID_2="DR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY_2="DR_SECRET_KEY"
export AWS_REGION_2="us-west-2"
```

Configure clusters:
- `cluster-primary`: credential_set=1, region=us-east-1
- `cluster-dr`: credential_set=2, region=us-west-2

## Best Practices

### Security

1. **Use IAM users with minimal permissions**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": [
         "ec2:RunInstances",
         "ec2:DescribeInstances",
         "ec2:TerminateInstances"
       ],
       "Resource": "*",
       "Condition": {
         "StringEquals": {
           "aws:RequestedRegion": "us-east-1"
         }
       }
     }]
   }
   ```

2. **Rotate credentials regularly**
   ```bash
   # Create new credentials monthly
   aws iam create-access-key --user-name openshift-deployer
   
   # Delete old credentials
   aws iam delete-access-key --user-name openshift-deployer --access-key-id OLD_KEY
   ```

3. **Use different IAM users per region/account**
   - Better audit trail
   - Easier to revoke specific access
   - Clearer cost attribution

4. **Never commit credentials to git**
   - All credential files are in `.gitignore`
   - Use environment variables only
   - Consider using a secrets manager

### Organization

1. **Use descriptive credential set assignments**
   ```yaml
   # Document in your host_vars files
   # Credential Set 1: Production account, us-east-1
   aws_credential_set: 1
   
   # Credential Set 2: Production account, us-west-2 (DR)
   aws_credential_set: 2
   
   # Credential Set 3: Development account, us-east-2
   aws_credential_set: 3
   ```

2. **Maintain a credential mapping document**
   ```
   Credential Set 1:
   - Account: Production (123456789012)
   - Region: us-east-1
   - Purpose: Primary production workloads
   - IAM User: openshift-prod-east
   
   Credential Set 2:
   - Account: Production (123456789012)
   - Region: us-west-2
   - Purpose: DR site
   - IAM User: openshift-prod-west
   
   Credential Set 3:
   - Account: Development (234567890123)
   - Region: us-east-2
   - Purpose: Development and testing
   - IAM User: openshift-dev
   ```

### Cost Management

1. **Tag resources by credential set**
   ```yaml
   # Automatically tagged by playbook
   Tags:
     - Key: credential-set
       Value: "1"
     - Key: environment
       Value: "production"
     - Key: region
       Value: "us-east-1"
   ```

2. **Use AWS Cost Explorer with tags**
   - Filter by credential-set tag
   - Track costs per region
   - Monitor across accounts

3. **Set up billing alerts per account**
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name openshift-monthly-cost \
     --comparison-operator GreaterThanThreshold \
     --evaluation-periods 1 \
     --metric-name EstimatedCharges \
     --namespace AWS/Billing \
     --period 86400 \
     --statistic Maximum \
     --threshold 500
   ```

## Validation

### Test Credentials

```bash
# Validate all credential sets
./ansible-runner.sh validate

# Or manually test each set
./ansible-runner.sh shell

# Inside container
aws sts get-caller-identity --region us-east-1 \
  --access-key-id $AWS_ACCESS_KEY_ID_1 \
  --secret-access-key $AWS_SECRET_ACCESS_KEY_1

aws sts get-caller-identity --region us-west-2 \
  --access-key-id $AWS_ACCESS_KEY_ID_2 \
  --secret-access-key $AWS_SECRET_ACCESS_KEY_2
```

### Verify Permissions

```bash
# Test EC2 permissions
aws ec2 describe-instances --region us-east-1

# Test VPC access
aws ec2 describe-vpcs --region us-east-1

# Test Route53 access (if using)
aws route53 list-hosted-zones
```

## Troubleshooting

### Credential Not Found

```
Error: AWS credentials not found for credential set 2
```

**Solution**: Set the missing environment variables
```bash
export AWS_ACCESS_KEY_ID_2="..."
export AWS_SECRET_ACCESS_KEY_2="..."
export AWS_REGION_2="us-west-2"
```

### Wrong Region

```
Error: AMI not found in region us-west-2
```

**Solution**: Either:
1. Update AMI ID for the correct region in host_vars
2. Or verify AWS_REGION_X matches the cluster's aws_region

### Permission Denied

```
Error: User is not authorized to perform: ec2:RunInstances
```

**Solution**: Review IAM permissions for the IAM user/role

### Account Mismatch

```
Error: VPC vpc-xxx not found
```

**Solution**: Verify you're using the correct credential set for the account where the VPC exists

## Environment Variable Management

### Using a Script

Create `set-aws-credentials.sh`:

```bash
#!/bin/bash
# Source this file: source set-aws-credentials.sh

# Production account
export AWS_ACCESS_KEY_ID_1="prod-key"
export AWS_SECRET_ACCESS_KEY_1="prod-secret"
export AWS_REGION_1="us-east-1"

# Staging account
export AWS_ACCESS_KEY_ID_2="staging-key"
export AWS_SECRET_ACCESS_KEY_2="staging-secret"
export AWS_REGION_2="us-west-2"

# Development account
export AWS_ACCESS_KEY_ID_3="dev-key"
export AWS_SECRET_ACCESS_KEY_3="dev-secret"
export AWS_REGION_3="eu-west-1"

echo "AWS credentials loaded for 3 accounts"
```

Usage:
```bash
source set-aws-credentials.sh
./ansible-runner.sh deploy
```

### Using AWS Profiles (Alternative)

While this tool uses numbered credentials, you can populate them from AWS profiles:

```bash
# Load from different profiles
export AWS_ACCESS_KEY_ID_1=$(aws configure get aws_access_key_id --profile prod)
export AWS_SECRET_ACCESS_KEY_1=$(aws configure get aws_secret_access_key --profile prod)
export AWS_REGION_1=$(aws configure get region --profile prod)

export AWS_ACCESS_KEY_ID_2=$(aws configure get aws_access_key_id --profile staging)
export AWS_SECRET_ACCESS_KEY_2=$(aws configure get aws_secret_access_key --profile staging)
export AWS_REGION_2=$(aws configure get region --profile staging)
```

## Summary

The multi-credential system provides:
- ✅ Flexibility to deploy across regions and accounts
- ✅ Security through credential isolation
- ✅ Cost tracking and management
- ✅ Organizational boundaries
- ✅ Disaster recovery capabilities

Each cluster independently chooses which credential set to use, enabling true multi-region and multi-account deployments.
