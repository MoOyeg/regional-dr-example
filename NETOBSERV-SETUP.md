# NetObserv Network Traffic Monitoring Setup

This guide explains how to use the `./ansible-runner.sh netobserv` command to install NetObserv for network traffic analysis with Loki log backend and S3 storage.

## Overview

The `netobserv` command automates the installation of:
1. **Loki Operator** - For centralized log aggregation
2. **LokiStack** - With S3 backend for persistent storage
3. **NetObserv Operator** - For network flow collection
4. **FlowCollector** - eBPF-based network traffic monitoring

This creates a complete network traffic analysis platform that collects flows from all cluster nodes and stores them in S3-backed Loki.

## Architecture

```
┌─────────────────────────────────────────────────┐
│         OpenShift Cluster                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  FlowCollector (netobserv namespace)    │  │
│  │  - eBPF agents on all nodes             │  │
│  │  - Captures network flows               │  │
│  └─────────────────┬────────────────────────┘  │
│                    │ sends flows               │
│                    ▼                           │
│  ┌──────────────────────────────────────────┐  │
│  │  Loki (openshift-logging namespace)     │  │
│  │  - Aggregates network flows             │  │
│  │  - Provides query interface             │  │
│  └─────────────────┬────────────────────────┘  │
│                    │ stores in                 │
│                    ▼                           │
│        ┌───────────────────────┐              │
│        │  AWS S3 Bucket        │              │
│        │  (netobserv-loki-...) │              │
│        └───────────────────────┘              │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Deployed Cluster
Your cluster must be deployed:
```bash
./ansible-runner.sh deploy
```

### 2. NetObserv Label in Inventory
Enable NetObserv on clusters by adding `netobserv: true` in their host_vars:

```bash
cat > inventory/host_vars/cluster-netobserv.yml <<'EOF'
cluster_name: cluster-netobserv
aws_credential_set: 1
aws_region: us-east-1
netobserv: true          # Enable NetObserv monitoring
EOF
```

### 3. AWS Credentials with S3 Permissions
Set AWS credentials for your cluster:
```bash
export AWS_ACCESS_KEY_ID_1="your-access-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret-key"
export AWS_REGION_1="us-east-1"
```

**Required IAM Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "*"
    }
  ]
}
```

## Installation

### Install NetObserv on All Clusters with netobserv: true
```bash
./ansible-runner.sh netobserv
```

### Install on Specific Cluster
```bash
./ansible-runner.sh netobserv --limit cluster-netobserv
```

### Verbose Output for Debugging
```bash
./ansible-runner.sh netobserv -v
```

## What Gets Installed

### 1. S3 Bucket Creation
- Unique bucket per cluster: `netobserv-loki-<cluster>-<region>-<timestamp>`
- Versioning enabled for data protection
- Tagged with cluster name and managed-by label

### 2. Loki Operator (openshift-logging namespace)
- Installed from Red Hat OperatorHub
- Channel: `stable` (default)
- Provides LokiStack custom resource

### 3. LokiStack Configuration
- **Size**: 1x.small (suitable for SNO clusters)
- **Storage**: S3 backend with versioning
- **Retention**: 7 days default
- **Multi-tenancy**: OpenShift logging mode

### 4. NetObserv Operator (netobserv namespace)
- Installed from Red Hat OperatorHub
- Channel: `stable` (default)
- Provides FlowCollector custom resource

### 5. FlowCollector Configuration
- **Agent Type**: eBPF (kernel-based, efficient)
- **Traffic Collection**: Network flows from all nodes
- **Backend**: Loki via HTTP
- **Tenant**: netobserv
- **Deployment**: Direct (no separate processor)

## Verification

### Check Loki Installation
```bash
# View LokiStack
oc get lokistack -n openshift-logging

# Check LokiStack status
oc describe lokistack loki -n openshift-logging

# Check Loki pods
oc get pods -n openshift-logging -l app.kubernetes.io/name=loki
```

### Check NetObserv Installation
```bash
# View FlowCollector
oc get flowcollector -n netobserv

# Check FlowCollector status
oc describe flowcollector cluster -n netobserv

# Check NetObserv operator pod
oc get pods -n netobserv
```

### Check eBPF Agent Pods
```bash
# View flow-collector agents on all nodes
oc get pods -n netobserv -l app=netobserv-ebpf-agent

# Check agent logs
oc logs -n netobserv -l app=netobserv-ebpf-agent --tail=50
```

### Check S3 Bucket
```bash
# List buckets
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls --region us-east-1

# Check bucket contents
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls s3://netobserv-loki-<cluster>-<region>-<timestamp>/ --recursive
```

## Accessing Network Traffic Data

### Via Loki CLI
```bash
# Get into a Loki pod
oc exec -it -n openshift-logging deployment/loki-distributor -- /bin/sh

# Query flows
loki-logcli query '{job="netobserv-flows"}'
```

### Via NetObserv Web UI (if installed)
```bash
# Port-forward to NetObserv UI
oc port-forward -n netobserv svc/netobserv-ui 3000:3000

# Open browser
open http://localhost:3000
```

### Via oc commands
```bash
# Check network flows in logs
oc logs -n openshift-logging -l app.kubernetes.io/name=loki --tail=100 | head -20

# Monitor flow collection
oc get events -n netobserv --sort-by='.lastTimestamp'
```

## Monitoring Flow Collection

### Check Agent Health
```bash
# View eBPF agent status
oc top nodes                          # CPU/memory usage
oc top pods -n netobserv             # NetObserv pod usage

# Check agent packet capture
oc exec -it -n netobserv <agent-pod> -- \
  cat /proc/net/dev                  # Interface statistics
```

### Monitor Loki Storage
```bash
# Check S3 usage
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls s3://netobserv-loki-<cluster>/ --recursive --summarize

# Check Loki disk usage
oc exec -it -n openshift-logging <loki-pod> -- \
  du -sh /loki
```

## Troubleshooting

### FlowCollector Stuck in Pending
**Check for errors:**
```bash
oc describe flowcollector cluster -n netobserv
oc logs -n netobserv -l app=netobserv-operator
```

**Common issues:**
- Insufficient resources on nodes
- Network policies blocking traffic
- Missing or invalid Loki endpoint

### Loki Not Starting
**Check Loki operator logs:**
```bash
oc logs -n openshift-logging -l app.kubernetes.io/name=loki-operator
```

**Common issues:**
- S3 credentials invalid
- Bucket doesn't exist or not accessible
- Insufficient PVC storage

### No Flows Being Collected
**Check eBPF agent logs:**
```bash
oc logs -n netobserv -l app=netobserv-ebpf-agent --tail=100
```

**Common issues:**
- eBPF not supported on kernel version
- Traffic filtering too aggressive
- Loki endpoint unreachable

### S3 Bucket Access Denied
**Verify AWS credentials and permissions:**
```bash
# Test S3 access
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls --region us-east-1

# Check IAM permissions
aws iam get-user-policy --user-name <username> --policy-name <policy>
```

## Configuration Customization

### Custom Operator Channels
Override in cluster host_vars:
```yaml
loki_channel: "testing"       # Instead of stable
netobserv_channel: "testing"
```

### Custom Retention Period
Edit LokiStack after creation:
```bash
oc patch lokistack loki -n openshift-logging --type merge -p \
  '{"spec":{"limits":{"global":{"retention":{"days":14}}}}}'
```

### Increase Storage Size
Edit LokiStack:
```bash
oc patch lokistack loki -n openshift-logging --type merge -p \
  '{"spec":{"size":"1x.medium"}}'
```

## Removing NetObserv

To remove NetObserv and clean up resources:
```bash
./ansible-runner.sh netobserv --destroy
```

This will:
- Delete FlowCollector
- Delete NetObserv operator
- Delete LokiStack
- Delete Loki operator
- Empty and delete S3 bucket
- Clean up all secrets and credentials

## Advanced Topics

### Multi-Cluster Aggregation
Configure all clusters to use central S3 bucket:
1. Create single S3 bucket with global access
2. Use same bucket in all clusters' LokiStack
3. Query across all cluster flows in single Loki instance

### Custom Sampling
Adjust packet sampling in FlowCollector (in setup-netobserv.yml):
```yaml
sampling: 400  # Sample 1 in 400 packets
```

### High-Volume Deployments
For large clusters, increase resources:
```bash
oc patch flowcollector cluster -n netobserv --type merge -p \
  '{"spec":{"processor":{"resources":{"limits":{"cpu":"2","memory":"2Gi"}}}}}'
```

## References

- [NetObserv Documentation](https://docs.openshift.com/container-platform/latest/networking/netobserv/about-netobserv.html)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [S3 Compatible Storage](https://grafana.com/docs/loki/latest/storage/s3/)
