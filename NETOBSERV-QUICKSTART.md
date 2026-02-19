# NetObserv Quick Start Guide

## 1. Enable NetObserv on a Cluster

Create `inventory/host_vars/cluster-netobserv.yml`:
```yaml
cluster_name: "cluster-netobserv"
aws_credential_set: 1
aws_region: "us-east-1"
netobserv: true
```

Add to `inventory/hosts`:
```
[openshift_clusters]
cluster-netobserv
```

## 2. Set AWS Credentials

```bash
export AWS_ACCESS_KEY_ID_1="your-access-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret-key"
export AWS_REGION_1="us-east-1"
```

**Required AWS Permissions:**
```json
{
  "Action": [
    "s3:CreateBucket", "s3:DeleteBucket",
    "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
    "s3:PutBucketVersioning", "s3:PutBucketTagging"
  ],
  "Resource": "*"
}
```

## 3. Install NetObserv

```bash
# Deploy cluster first
./ansible-runner.sh deploy

# Then install NetObserv
./ansible-runner.sh netobserv
```

Or install on specific cluster:
```bash
./ansible-runner.sh netobserv --limit cluster-netobserv
```

## 4. Verify Installation

```bash
# Check Loki
oc get lokistack -n openshift-logging

# Check NetObserv
oc get flowcollector -n netobserv

# Check eBPF agents
oc get pods -n netobserv -l app=netobserv-ebpf-agent
```

## 5. Query Network Flows

### Via Loki CLI
```bash
oc exec -it -n openshift-logging deployment/loki-distributor -- /bin/sh
loki-logcli query '{job="netobserv-flows"}'
```

### Via NetObserv UI
```bash
oc port-forward -n netobserv svc/netobserv-ui 3000:3000
# Open http://localhost:3000
```

### Via Kubectl Logs
```bash
oc logs -n openshift-logging -l app.kubernetes.io/name=loki --tail=100
```

## 6. What Gets Created

### Automatically Provisioned
- ✓ S3 Bucket: `netobserv-loki-<cluster>-<region>-<timestamp>`
- ✓ Loki Operator: `openshift-logging` namespace
- ✓ LokiStack: Configured with S3 backend
- ✓ NetObserv Operator: `netobserv` namespace
- ✓ FlowCollector: With eBPF agents on all nodes

### Default Configuration
- **S3 Bucket**: Versioning enabled, 7-day retention
- **Loki Deployment**: 1x.small (suitable for SNO)
- **Storage Backend**: AWS S3
- **Flow Sampling**: 1 in 400 packets
- **Agent Type**: eBPF (kernel-based, efficient)

## 7. Cleanup

Remove NetObserv and delete S3 bucket:
```bash
./ansible-runner.sh netobserv --destroy
```

Or specific cluster:
```bash
./ansible-runner.sh netobserv --limit cluster-netobserv --destroy
```

## 8. Troubleshooting

### FlowCollector not ready
```bash
oc describe flowcollector cluster -n netobserv
oc logs -n netobserv -l app=netobserv-operator
```

### Loki not starting
```bash
oc logs -n openshift-logging -l app.kubernetes.io/name=loki-operator
oc get lokistack loki -n openshift-logging -o yaml
```

### S3 access denied
```bash
# Verify credentials
AWS_ACCESS_KEY_ID_1="..." AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls --region us-east-1
```

### No flows being collected
```bash
oc logs -n netobserv -l app=netobserv-ebpf-agent
oc describe flowcollector cluster -n netobserv
```

## 9. Common Commands

```bash
# Install on all enabled clusters
./ansible-runner.sh netobserv

# Install on specific cluster
./ansible-runner.sh netobserv --limit cluster-name

# Verbose output
./ansible-runner.sh netobserv -v

# Remove NetObserv
./ansible-runner.sh netobserv --destroy

# Check Loki status
oc get lokistack -n openshift-logging

# Check NetObserv status
oc get flowcollector -n netobserv

# Access UI
oc port-forward -n netobserv svc/netobserv-ui 3000:3000

# View logs
oc logs -n netobserv -l app=netobserv-ebpf-agent -f

# Check S3
aws s3 ls --region us-east-1 | grep netobserv
```

## 10. Configuration

### Override Operator Channels
In `inventory/host_vars/cluster.yml`:
```yaml
netobserv: true
loki_channel: "testing"        # Instead of stable
netobserv_channel: "testing"
```

### Customize Retention
After installation:
```bash
oc patch lokistack loki -n openshift-logging --type merge -p \
  '{"spec":{"limits":{"global":{"retention":{"days":14}}}}}'
```

### Increase Deployment Size
```bash
oc patch lokistack loki -n openshift-logging --type merge -p \
  '{"spec":{"size":"1x.medium"}}'
```

## Reference

- Full documentation: [NETOBSERV-SETUP.md](./NETOBSERV-SETUP.md)
- Implementation details: [NETOBSERV-IMPLEMENTATION.md](./NETOBSERV-IMPLEMENTATION.md)
- Example configuration: [inventory/host_vars/cluster-netobserv.example](./inventory/host_vars/cluster-netobserv.example)
