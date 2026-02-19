# Auto-Detecting Base Domain from Route53

This feature allows you to omit `cluster_base_domain` from your cluster configuration. The script will automatically query Route53 using the appropriate AWS credentials and use the first hosted zone.

## How It Works

1. **Query Route53**: Uses the AWS credentials for the specified credential set to list hosted zones
2. **Select First Zone**: Takes the first hosted zone from the list
3. **Set Base Domain**: Uses this as the `cluster_base_domain`
4. **Fail Gracefully**: If no hosted zones are found, deployment fails with a clear error message

## Example Configuration

### Without Auto-Detection (Traditional)

```yaml
cluster_name: "cluster-us-east-1"
cluster_base_domain: "example.com"  # Explicitly specified
aws_credential_set: 1
# ... other config
```

### With Auto-Detection (New Feature)

```yaml
cluster_name: "cluster-us-east-1"
# cluster_base_domain not specified - will auto-detect!
aws_credential_set: 1
# ... other config
```

## Use Cases

### Use Case 1: Single Hosted Zone

If you have only one hosted zone in Route53:

```yaml
# Your Route53 has: example.com
cluster_name: "cluster-primary"
# cluster_base_domain will be auto-detected as "example.com"
aws_credential_set: 1
```

Result: Cluster will use `example.com` as base domain

### Use Case 2: Multiple Hosted Zones

If you have multiple hosted zones, the first one will be used:

```yaml
# Your Route53 has: example.com, dev.example.com, prod.example.com
cluster_name: "cluster-primary"
# cluster_base_domain will be auto-detected as "example.com" (first zone)
aws_credential_set: 1
```

Result: Cluster will use the first zone alphabetically

### Use Case 3: Different Zones per Credential Set

Each credential set can point to a different AWS account with different hosted zones:

```yaml
# Credential Set 1 Route53: prod.example.com
# Credential Set 2 Route53: staging.example.com
# Credential Set 3 Route53: dev.example.com

# Cluster 1 - will auto-detect prod.example.com
cluster_name: "cluster-prod"
aws_credential_set: 1

# Cluster 2 - will auto-detect staging.example.com
cluster_name: "cluster-staging"
aws_credential_set: 2

# Cluster 3 - will auto-detect dev.example.com
cluster_name: "cluster-dev"
aws_credential_set: 3
```

## Deployment Output

When auto-detection is used, you'll see:

```
TASK [Display cluster deployment information] *****
ok: [cluster-us-east-1] => {
    "msg": "Deploying cluster: cluster-us-east-1\nRegion: us-east-1\nCredential Set: 1\nBase Domain: example.com\n(auto-detected from Route53)"
}
```

## Benefits

1. **Less Configuration**: No need to specify the domain if you have Route53 hosted zones
2. **Account-Specific**: Each AWS credential can use its own hosted zone
3. **Flexible**: You can still override by explicitly setting `cluster_base_domain`
4. **Safe**: Fails clearly if no hosted zones are found

## Troubleshooting

### No Hosted Zones Found

```
Error: cluster_base_domain is not defined and no Route53 hosted zones found in AWS account
```

**Solution**: Either:
1. Create a hosted zone in Route53
2. Or explicitly set `cluster_base_domain` in your cluster configuration

### Wrong Zone Selected

If you have multiple hosted zones and the first one isn't what you want:

**Solution**: Explicitly set `cluster_base_domain` in your configuration:

```yaml
cluster_name: "cluster-us-east-1"
cluster_base_domain: "prod.example.com"  # Override auto-detection
aws_credential_set: 1
```

### Permission Denied

```
Error: An error occurred (AccessDenied) when calling the ListHostedZones operation
```

**Solution**: Ensure your IAM user/role has `route53:ListHostedZones` permission

## Best Practice

- **Use auto-detection** when you have one hosted zone per AWS account
- **Use explicit domain** when you have multiple zones or need precise control
- **Document in comments** which approach you're using:

```yaml
# Using auto-detection from Route53
cluster_name: "cluster-us-east-1"
# cluster_base_domain: will use first Route53 zone
aws_credential_set: 1
```

Or:

```yaml
# Explicitly setting domain (multiple zones in account)
cluster_name: "cluster-us-east-1"
cluster_base_domain: "prod.example.com"  # Using prod zone, not dev
aws_credential_set: 1
```
