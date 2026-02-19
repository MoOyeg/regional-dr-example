# NetObserv ACM OperatorPolicy Fallback Strategy

## Overview
The `setup-netobserv.yml` playbook now intelligently detects whether Advanced Cluster Management (ACM) is available on your cluster and adapts installation accordingly.

## Detection Logic

### Play 2 (Loki Operator) & Play 3 (NetObserv Operator)
Both plays now check for the OperatorPolicy CRD:

```bash
oc api-resources | grep -i operatorpolicy
```

Based on availability:
- **Available** (`use_operatorpolicy: true`): Deploy via ACM OperatorPolicy
- **Not Available** (`use_operatorpolicy: false`): Deploy via direct Subscription

## Installation Modes

### Mode 1: ACM OperatorPolicy (Preferred)
When ACM policies framework is installed on the cluster:

```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: OperatorPolicy
metadata:
  name: loki-operator-policy
  namespace: openshift-logging
spec:
  remediationAction: enforce          # Self-healing enabled
  severity: critical
  complianceType: musthave             # Auto-remediation on drift
  operatorGroup: {...}
  subscription: {...}
```

**Benefits:**
- ✅ Self-healing operator management
- ✅ Automatic drift detection and remediation
- ✅ Compliance status reporting
- ✅ Multi-cluster consistency via hub

### Mode 2: Direct Subscription (Fallback)
When ACM OperatorPolicy CRD is not found:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-logging
spec:
  channel: stable
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**Benefits:**
- ✅ Works on any OpenShift 4.20+ cluster
- ✅ No ACM dependency
- ⚠️ No automatic self-healing (manual intervention if misconfigured)

## Playbook Behavior

### Setup Flow

```
setup-netobserv.yml
├── Play 1: S3 Bucket Provisioning (unchanged - always runs)
│
├── Play 2: Loki Operator Installation
│   ├── Check: OperatorPolicy CRD available?
│   ├── If YES → Deploy via OperatorPolicy (1 task)
│   │   └── Wait for policy compliance
│   └── If NO → Deploy via OperatorGroup + Subscription (2 tasks)
│       └── Wait for CSV success
│
├── Create S3 Credentials Secret (unchanged - both modes)
├── Deploy LokiStack (unchanged - both modes)
│
├── Play 3: NetObserv Operator Installation
│   ├── Check: OperatorPolicy CRD available?
│   ├── If YES → Deploy via OperatorPolicy (1 task)
│   │   └── Wait for policy compliance
│   └── If NO → Deploy via OperatorGroup + Subscription (2 tasks)
│       └── Wait for CSV success
│
└── Deploy FlowCollector (unchanged - both modes)
```

### Destroy Flow

The `destroy-netobserv.yml` playbook handles cleanup automatically:

```yaml
tasks:
  - Delete FlowCollector (both modes)
  - Delete OperatorPolicy (if it exists) - ignored if not found
  - Delete OperatorGroup (cleanup fallback)
  - Delete Subscription (cleanup fallback)
  - Delete namespace
  - Delete LokiStack
  - Delete S3 bucket
```

All deletion operations use `--ignore-not-found` to gracefully handle both installation modes.

## Debugging

### Check Which Mode Was Used
Run the playbook with verbose flag:

```bash
./ansible-runner.sh netobserv --limit cluster1 -v
```

Look for this task output:
```
TASK [Display installation method]
msg:
  Installation Method: ACM OperatorPolicy
  # OR
  Installation Method: Direct Subscription
  NOTE: ACM OperatorPolicy CRD not found. Using direct Subscription-based installation.
```

### Verify Operator Installation

**If using ACM OperatorPolicy:**
```bash
oc get operatorpolicy -n openshift-logging
oc get operatorpolicy -n netobserv
# Check compliance status
oc describe operatorpolicy loki-operator-policy -n openshift-logging
```

**If using Direct Subscription:**
```bash
oc get subscription -n openshift-logging
oc get subscription -n netobserv
# Check ClusterServiceVersion status
oc get csv -n openshift-logging
oc get csv -n netobserv
```

### Check Operator Readiness (Both Modes)
```bash
# Check installed operators
oc get deployment -n openshift-logging
oc get deployment -n netobserv

# Verify Loki is ready
oc get lokistack loki -n openshift-logging

# Verify FlowCollector is ready
oc get flowcollector -n netobserv
```

## Upgrading to ACM OperatorPolicy

If you have a cluster running with direct Subscriptions and want to migrate to ACM OperatorPolicy:

1. **Install ACM** on the hub cluster:
   ```bash
   ./ansible-runner.sh operators
   ```

2. **Import spoke clusters** (if not already imported):
   ```bash
   ./ansible-runner.sh import --limit <cluster>
   ```

3. **Re-run NetObserv setup**:
   ```bash
   ./ansible-runner.sh netobserv --limit <cluster>
   ```

The playbook will detect the newly available OperatorPolicy CRD and automatically create ACM OperatorPolicy resources alongside the existing Subscriptions. You can then manually delete the old Subscriptions if desired.

## Troubleshooting

### Error: "no matches for kind OperatorPolicy"
This means ACM policies framework is not installed. The playbook will automatically fall back to direct Subscriptions. This is expected on standalone OpenShift clusters without ACM.

**Resolution:** Either (1) Install ACM, or (2) Proceed with direct Subscription mode (no further action needed).

### OperatorPolicy shows Non-Compliant
If using ACM OperatorPolicy and status shows `Compliant: false`:

```bash
# Check the policy status details
oc describe operatorpolicy loki-operator-policy -n openshift-logging

# Look for .status.details[].compliant-message for specific issues
```

Common issues:
- Operator not in OperatorHub channel specified
- Missing OperatorGroup
- Insufficient RBAC permissions
- Resource quota limits exceeded

### Operators not appearing after 5 minutes
Loki and NetObserv operator installations include 60 retries with 10-second delays (10 minutes maximum).

**If still pending after 10 minutes:**
```bash
# Check OperatorHub connectivity
oc get operatorhubs.config.openshift.io cluster

# Check Operator Marketplace
oc get pods -n openshift-marketplace

# Check if operator source is available
oc get catalogsource -n openshift-marketplace | grep redhat-operators
```

## Migration Notes

- **Play 1 (S3 Bucket):** Unchanged - runs regardless of installation mode
- **Custom Resources:** LokiStack and FlowCollector creation unchanged - works with both modes
- **Destroy:** Both installation modes cleaned up by same destroy playbook
- **Backward Compatible:** Clusters with existing Subscriptions continue to work

## Next Steps

For additional configuration and monitoring:
- Review [NETOBSERV-SETUP.md](NETOBSERV-SETUP.md) for detailed configuration options
- See [NETOBSERV-QUICKSTART.md](NETOBSERV-QUICKSTART.md) for rapid deployment
- Check [NETOBSERV-ACM-POLICY.md](NETOBSERV-ACM-POLICY.md) for ACM-specific benefits and architecture
