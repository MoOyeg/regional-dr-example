# NetObserv with ACM OperatorPolicy

## Overview

The `./ansible-runner.sh netobserv` command now uses **ACM OperatorPolicy** to manage operator installations instead of direct Ansible Subscription/OperatorGroup resources.

## Benefits of OperatorPolicy Approach

### 1. Policy-Based Management
- **Declarative**: Define desired state once
- **Compliant Enforcement**: ACM continuously enforces policy compliance
- **Automatic Remediation**: ACM auto-corrects drift
- **Multi-Cluster**: Single policy can target multiple clusters

### 2. Consistency
- All clusters follow the same operator configuration
- Policy version control in Git
- Audit trail of changes
- Compliance reporting

### 3. Integration with ACM
- Managed through ACM console
- Policy status visible in ACM
- Automatic policy evaluation
- Integration with other ACM policies

### 4. Self-Healing
- If someone manually modifies or deletes operators, ACM restores them
- Ensures operators stay in desired state
- No manual intervention needed

## Architecture

```
┌─────────────────────────────────────────┐
│  setup-netobserv.yml                    │
├─────────────────────────────────────────┤
│ Play 1: S3 Bucket (Ansible)             │
│ ├─ Create S3 bucket                     │
│ └─ Store credentials                    │
│                                         │
│ Play 2: Loki OperatorPolicy (ACM)       │
│ ├─ Create OperatorPolicy for Loki       │
│ └─ Wait for policy to be Compliant      │
│                                         │
│ Play 3: NetObserv OperatorPolicy (ACM)  │
│ ├─ Create OperatorPolicy for NetObserv  │
│ ├─ Create FlowCollector                 │
│ └─ Wait for policy to be Compliant      │
└─────────────────────────────────────────┘
        ↓
    Cluster
        ↓
    ┌─────────────────┐
    │  ACM Framework  │
    │  - Evaluates    │
    │  - Enforces     │
    │  - Reports      │
    └─────────────────┘
        ↓
    ┌────────────────────────────────────┐
    │  OperatorPolicy Resources          │
    ├────────────────────────────────────┤
    │  - loki-operator-policy            │
    │  - netobserv-operator-policy       │
    └────────────────────────────────────┘
        ↓
    ┌────────────────────────────────────┐
    │  Installed Operators               │
    ├────────────────────────────────────┤
    │  - Loki Operator                   │
    │  - NetObserv Operator              │
    │  - FlowCollector (custom resource) │
    └────────────────────────────────────┘
```

## OperatorPolicy Specification

### Loki OperatorPolicy
```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: OperatorPolicy
metadata:
  name: loki-operator-policy
  namespace: openshift-logging
spec:
  remediationAction: enforce      # Auto-correct drift
  severity: critical              # Critical if non-compliant
  complianceType: musthave        # Must have this operator
  operatorGroup:
    name: openshift-logging
    namespace: openshift-logging
    targetNamespaces:
      - openshift-logging
  subscription:
    name: loki-operator
    namespace: openshift-logging
    channel: stable
    installPlanApproval: Automatic
    source: redhat-operators
    sourceNamespace: openshift-marketplace
    package: loki-operator
```

### NetObserv OperatorPolicy
```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: OperatorPolicy
metadata:
  name: netobserv-operator-policy
  namespace: netobserv
spec:
  remediationAction: enforce
  severity: critical
  complianceType: musthave
  operatorGroup:
    name: netobserv-operator
    namespace: netobserv
    targetNamespaces:
      - netobserv
  subscription:
    name: netobserv-operator
    namespace: netobserv
    channel: stable
    installPlanApproval: Automatic
    source: redhat-operators
    sourceNamespace: openshift-marketplace
    package: netobserv-operator
```

## How It Works

### 1. Policy Creation
- Ansible creates OperatorPolicy resources on the cluster
- Policies define desired operator configuration
- `remediationAction: enforce` enables auto-remediation

### 2. Compliance Evaluation
- ACM policy framework evaluates policies
- Checks if operators are installed per policy
- Reports compliance status

### 3. Enforcement
- If operators missing: ACM installs them
- If operators modified: ACM restores to policy state
- If operators deleted: ACM reinstalls automatically

### 4. Status Reporting
- Policy status stored in `.status.compliant`
- `Compliant` = operators installed and correct
- `NonCompliant` = drift detected, being corrected

## Verification

### Check OperatorPolicy Status
```bash
# View Loki OperatorPolicy
oc get operatorpolicy loki-operator-policy -n openshift-logging

# View NetObserv OperatorPolicy
oc get operatorpolicy netobserv-operator-policy -n netobserv

# Get detailed status
oc describe operatorpolicy loki-operator-policy -n openshift-logging
```

### Check Operator Installation Status
```bash
# View installed operators via policy
oc get subscription -n openshift-logging
oc get subscription -n netobserv

# View CSV status
oc get csv -n openshift-logging
oc get csv -n netobserv
```

### Check Policy Compliance
```bash
# List all policies on cluster
oc get operatorpolicy -A

# Check specific policy compliance
oc get operatorpolicy loki-operator-policy -n openshift-logging \
  -o jsonpath='{.status.compliant}'
# Output: Compliant or NonCompliant
```

## Comparison: OperatorPolicy vs Direct Subscription

### Direct Subscription (Old Approach)
```
Ansible Creates Subscription
    ↓
OLM Processes Subscription
    ↓
Operator Installed
    ↓
Manual management if anything changes
```

### OperatorPolicy (New Approach)
```
Ansible Creates OperatorPolicy
    ↓
ACM Framework Evaluates Policy
    ↓
ACM Enforces Compliance
    ↓
Operator Installed & Self-Healing
    ↓
Automatic drift correction
```

## Self-Healing Example

If someone accidentally deletes the Loki operator:

```bash
oc delete subscription loki-operator -n openshift-logging
```

**What happens:**
1. ACM detects policy is non-compliant
2. ACM reads policy definition
3. ACM recreates the subscription
4. Loki operator automatically reinstalls

**No manual intervention needed!**

## Multi-Cluster Deployment

OperatorPolicy enables multi-cluster deployments:

```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: ConfigurationPolicy
metadata:
  name: netobserv-policies
spec:
  remediationAction: enforce
  severity: critical
  objectDefinition:
    apiVersion: policy.open-cluster-management.io/v1
    kind: OperatorPolicy
    metadata:
      name: loki-operator-policy
      namespace: openshift-logging
    # ... operator policy spec ...
---
apiVersion: apps.open-cluster-management.io/v1
kind: Placement
metadata:
  name: netobserv-placement
spec:
  predicates:
  - requiredClusterSelector:
      labelSelector:
        matchLabels:
          netobserv: "true"
```

Deploy to multiple clusters at once!

## Troubleshooting

### Policy Not Compliant

**Check policy status:**
```bash
oc describe operatorpolicy loki-operator-policy -n openshift-logging
```

**Common issues:**
1. **Subscription not created**: Check namespace permissions
2. **Channel not found**: Verify operator channel name
3. **Source not available**: Check OperatorHub access

### Operator Not Installing

**Check policy logs:**
```bash
oc logs -n openshift-logging -l app=policy-controller

# Or check OLM logs
oc logs -n openshift-operator-lifecycle-manager deployment/olm-operator
```

### Policy Won't Become Compliant

**Debug steps:**
```bash
# Check if subscription was created by policy
oc get subscription -n openshift-logging

# Check CSV status
oc get csv -n openshift-logging

# Get policy detailed status
oc get operatorpolicy loki-operator-policy -n openshift-logging -o yaml | grep -A 20 status:
```

## Advanced Configuration

### Change Remediation Action to Inform Only

To only report issues without auto-fixing:

```yaml
spec:
  remediationAction: inform    # Just report, don't fix
```

### Target Specific Channels

Override channel in cluster host_vars:
```yaml
loki_channel: "testing"     # Use testing channel instead of stable
```

### Policy Severity Levels

```yaml
severity: critical     # Highest priority
severity: high        # Important
severity: medium      # Normal
severity: low         # Low priority
```

## References

- [ACM OperatorPolicy Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.x/html/governance/operator-policy)
- [Policy Framework](https://open-cluster-management.io/concepts/architecture/policy/)
- [Compliance and Remediation](https://open-cluster-management.io/concepts/architecture/policy/addon/#compliance)
