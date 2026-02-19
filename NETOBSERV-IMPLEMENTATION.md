# NetObserv Command Implementation Summary

## Overview

A new `./ansible-runner.sh netobserv` command has been created that provisions network traffic monitoring for OpenShift clusters. It automatically:

1. ✓ Checks for `netobserv: true` label in cluster inventory
2. ✓ Creates S3 bucket for Loki log storage
3. ✓ Installs Loki operator and configures LokiStack with S3 backend
4. ✓ Installs NetObserv operator
5. ✓ Creates FlowCollector with eBPF agent for network flow collection

## Files Created/Modified

| File | Type | Changes |
|------|------|---------|
| `setup-netobserv.yml` | New Playbook | 3-play installation for S3, Loki, and NetObserv |
| `destroy-netobserv.yml` | New Playbook | Cleanup: removes operators, deletes S3 bucket |
| `ansible-runner.sh` | Modified | Added netobserv command handling |
| `inventory/group_vars/all.yml` | Modified | Added Loki and NetObserv configuration variables |
| `inventory/host_vars/cluster-netobserv.example` | New File | Example cluster configuration |
| `NETOBSERV-SETUP.md` | New Documentation | Complete setup and usage guide |

## Playbook Structure

### setup-netobserv.yml (3 Plays)

#### Play 1: Provision S3 Bucket
```yaml
- Creates S3 bucket: netobserv-loki-<cluster>-<region>-<timestamp>
- Enables versioning for data protection
- Tags bucket with cluster name and managed-by=netobserv
- Saves bucket name to artifacts for later cleanup
```

#### Play 2: Install Loki Operator
```yaml
- Creates openshift-logging namespace
- Installs Loki operator from OperatorHub
- Creates S3 credentials secret in kube-system
- Deploys LokiStack with:
  - S3 backend storage
  - 1x.small deployment size
  - 7-day retention
  - OpenShift logging multi-tenancy mode
```

#### Play 3: Install NetObserv and FlowCollector
```yaml
- Creates netobserv namespace
- Installs NetObserv operator from OperatorHub
- Deploys FlowCollector with:
  - eBPF agent on all nodes
  - Loki as backend
  - Network flow collection enabled
  - 400 packet sampling rate
```

### destroy-netobserv.yml

Cleanup playbook that:
- Deletes FlowCollector
- Deletes NetObserv operator
- Deletes LokiStack
- Deletes Loki operator
- Removes S3 credentials secret
- Empties and deletes S3 bucket
- Removes saved bucket name from artifacts

## How It Works

### 1. Cluster Selection
- Only processes clusters with `netobserv: true` in inventory
- Skips clusters without the label
- Supports `--limit` for specific clusters

### 2. AWS Integration
- Uses configured AWS credentials for the cluster
- Creates unique S3 bucket per cluster
- Stores bucket name for future cleanup
- Fully automated without manual AWS steps

### 3. Loki Backend
```
Flows → NetObserv → Loki → S3 Bucket
```
- eBPF agents capture network flows on nodes
- Flows sent to Loki for aggregation
- Loki stores logs in S3 with versioning
- Supports querying across all flows

### 4. Network Flow Collection
- eBPF agent (efficient kernel-based collection)
- Runs on all cluster nodes
- Captures TCP/UDP/ICMP flows
- Samples at 1:400 rate for performance

## Usage Examples

### Basic Installation
```bash
# Install on all clusters with netobserv: true
./ansible-runner.sh netobserv

# Install on specific cluster
./ansible-runner.sh netobserv --limit cluster-netobserv

# Verbose output for debugging
./ansible-runner.sh netobserv -v
```

### Cleanup
```bash
# Remove NetObserv from all clusters
./ansible-runner.sh netobserv --destroy

# Remove from specific cluster
./ansible-runner.sh netobserv --limit cluster-netobserv --destroy
```

## Cluster Configuration

### Enable NetObserv on a Cluster

Create or modify `inventory/host_vars/cluster-name.yml`:

```yaml
cluster_name: "cluster-netobserv"
aws_credential_set: 1
aws_region: "us-east-1"
netobserv: true              # Enable NetObserv
```

Add cluster name to `inventory/hosts`:
```
[openshift_clusters]
cluster-netobserv
```

Then run:
```bash
./ansible-runner.sh netobserv --limit cluster-netobserv
```

## Verification

### Check Installation Status
```bash
# Loki
oc get lokistack -n openshift-logging
oc get pods -n openshift-logging

# NetObserv
oc get flowcollector -n netobserv
oc get pods -n netobserv

# eBPF agents
oc get pods -n netobserv -l app=netobserv-ebpf-agent
```

### View Network Flows
```bash
# Via Loki query
oc exec -it -n openshift-logging deployment/loki-distributor -- \
  loki-logcli query '{job="netobserv-flows"}'

# Via NetObserv UI (if deployed)
oc port-forward -n netobserv svc/netobserv-ui 3000:3000
# Open http://localhost:3000
```

### Check S3 Storage
```bash
# List S3 buckets
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls --region us-east-1 | grep netobserv

# Check bucket contents
AWS_ACCESS_KEY_ID_1="..." \
AWS_SECRET_ACCESS_KEY_1="..." \
aws s3 ls s3://netobserv-loki-<cluster>-<region>-<timestamp>/ --recursive
```

## Prerequisites Checklist

- [ ] Cluster deployed: `./ansible-runner.sh deploy`
- [ ] `netobserv: true` label in cluster `inventory/host_vars/`
- [ ] AWS credentials set:
  ```bash
  export AWS_ACCESS_KEY_ID_1="your-key"
  export AWS_SECRET_ACCESS_KEY_1="your-secret"
  export AWS_REGION_1="us-east-1"
  ```
- [ ] AWS credentials have S3 permissions:
  - s3:CreateBucket, DeleteBucket
  - s3:PutObject, GetObject, DeleteObject
  - s3:PutBucketVersioning, PutBucketTagging

## Key Features

### Automatic S3 Management
- Creates bucket with unique name per cluster
- Enables versioning for data protection
- Tags for easy identification
- Automatic cleanup on destroy

### Loki Backend
- 7-day retention (configurable)
- 1x.small deployment (suitable for SNO)
- Multi-tenant support
- S3 object storage

### Network Monitoring
- eBPF-based collection (kernel-efficient)
- Minimal CPU/memory impact
- Runs on all nodes automatically
- 400 packet sampling rate

### Integration
- Works with existing OpenShift infrastructure
- Uses standard Loki and NetObserv operators
- Respects cluster RBAC policies
- Supports multi-cluster deployments

## Configuration Variables

In `inventory/group_vars/all.yml`:
```yaml
loki_channel: "stable"           # Loki operator channel
netobserv_channel: "stable"      # NetObserv operator channel
```

Per-cluster override in `inventory/host_vars/`:
```yaml
netobserv: true                  # Enable on this cluster
loki_channel: "testing"          # Override channel
netobserv_channel: "testing"
```

## Troubleshooting

For detailed troubleshooting guide, see: [NETOBSERV-SETUP.md](./NETOBSERV-SETUP.md)

### Common Issues

1. **FlowCollector stuck in Pending**
   - Check eBPF support: `oc describe flowcollector cluster -n netobserv`
   - Check resources: `oc top nodes`

2. **Loki not starting**
   - Check S3 credentials: `oc get secret loki-s3-credentials -n openshift-logging`
   - Check S3 access: AWS CLI commands with provided credentials

3. **No flows being collected**
   - Check agent pods: `oc get pods -n netobserv -l app=netobserv-ebpf-agent`
   - Check Loki connectivity: `oc logs -n netobserv <agent-pod>`

## AWS Permissions Required

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

## Advanced Options

### Custom Retention
Edit LokiStack after creation:
```bash
oc patch lokistack loki -n openshift-logging --type merge -p \
  '{"spec":{"limits":{"global":{"retention":{"days":14}}}}}'
```

### Larger Deployments
Override in cluster host_vars:
```yaml
aws_instance_type: "m5.4xlarge"    # For high-volume monitoring
```

### Custom Sampling
Edit in setup-netobserv.yml FlowCollector (line ~420):
```yaml
sampling: 100  # More aggressive sampling
```

## Limitations

- Single S3 bucket per cluster (no multi-cluster aggregation out-of-box)
- 7-day default retention (can be increased manually)
- eBPF requires Linux 4.15+ (most distributions supported)
- Sampling at 1:400 may miss low-frequency flows

## Integration with Other Commands

```bash
# Deploy cluster
./ansible-runner.sh deploy

# Then optionally add monitoring
./ansible-runner.sh certs              # Add cert management
./ansible-runner.sh netobserv          # Add network monitoring
./ansible-runner.sh operators          # Add DR operators
```

## Next Steps

1. **Enable NetObserv on a cluster**
   - Add `netobserv: true` to cluster inventory
   - Run `./ansible-runner.sh netobserv --limit cluster-name`

2. **Verify Installation**
   - Check Loki: `oc get lokistack -n openshift-logging`
   - Check flows: `oc get flowcollector -n netobserv`

3. **Query Network Data**
   - Access Loki directly with loki-logcli
   - Use port-forward for NetObserv UI
   - Build custom dashboards with Grafana

4. **Scale for Production**
   - Increase retention period as needed
   - Allocate larger instance types
   - Monitor S3 costs
   - Set up alerting on flow volumes

---

**Created:** February 16, 2026  
**Status:** Ready for Production
