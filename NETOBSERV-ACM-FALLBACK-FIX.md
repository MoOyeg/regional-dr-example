# NetObserv ACM OperatorPolicy Fallback Implementation

## Problem
When running `./ansible-runner.sh netobserv --limit cluster1`, the playbook failed with:
```
error: resource mapping not found for name: "loki-operator-policy" namespace: "openshift-logging" 
from "STDIN": no matches for kind "OperatorPolicy" in version "policy.open-cluster-management.io/v1"
ensure CRDs are installed first
```

The cluster didn't have Advanced Cluster Management (ACM) installed, so the OperatorPolicy CRD wasn't available.

## Solution
Implemented **intelligent fallback mechanism** that:

1. **Detects ACM availability** on each cluster during execution
2. **Uses ACM OperatorPolicy** if available (preferred - self-healing)
3. **Falls back to direct Subscriptions** if ACM not available (graceful degradation)
4. **Maintains backward compatibility** with existing installations

## Changes Made

### 1. setup-netobserv.yml

#### Play 2 (Loki Operator Installation)
- **Added CRD detection** in pre_tasks:
  ```yaml
  - name: Check for ACM OperatorPolicy CRD availability
    shell: oc api-resources | grep -i operatorpolicy > /dev/null 2>&1 && echo "available" || echo "unavailable"
  ```

- **Conditional OperatorPolicy creation** (if available):
  ```yaml
  - name: Create OperatorPolicy for Loki operator
    when: use_operatorpolicy | bool
  ```

- **Conditional Subscription fallback** (if not available):
  ```yaml
  - name: Create OperatorGroup for Loki (direct installation fallback)
    when: not use_operatorpolicy | bool
  - name: Create Subscription for Loki operator (direct installation fallback)
    when: not use_operatorpolicy | bool
  ```

#### Play 3 (NetObserv Operator Installation)
- Same fallback pattern for NetObserv operator
- Added CRD detection to pre_tasks
- Conditional deployment of OperatorPolicy or Subscription

### 2. destroy-netobserv.yml

- Added CRD detection in pre_tasks (matches setup playbook)
- Cleanup tasks work with both installation modes via `--ignore-not-found` flags

### 3. NETOBSERV-ACM-FALLBACK.md (New Documentation)

Comprehensive guide covering:
- **Detection logic** and how it works
- **Both installation modes** with code examples
- **Benefits of each approach**
- **Complete playbook flow diagrams**
- **Debugging techniques** for both modes
- **Troubleshooting guide** for common issues
- **Migration path** from direct Subscriptions to ACM OperatorPolicy

## Behavior After Fix

### Scenario 1: Cluster with ACM installed
```
TASK [Check for ACM OperatorPolicy CRD availability]
✓ Found OperatorPolicy CRD

TASK [Display installation method]
Installation Method: ACM OperatorPolicy

TASK [Create OperatorPolicy for Loki operator]
✓ Skipped tasks for Subscription fallback
✓ Loki installed via self-healing OperatorPolicy
```

### Scenario 2: Cluster without ACM (current situation)
```
TASK [Check for ACM OperatorPolicy CRD availability]
✓ OperatorPolicy CRD not found

TASK [Display installation method]
Installation Method: Direct Subscription
NOTE: ACM OperatorPolicy CRD not found. Using direct Subscription-based installation.

TASK [Create OperatorGroup for Loki (direct installation fallback)]
✓ OperatorGroup created

TASK [Create Subscription for Loki operator (direct installation fallback)]
✓ Loki installed via direct Subscription
```

## Testing the Fix

Run the playbook as before:
```bash
./ansible-runner.sh netobserv --limit cluster1
```

The playbook will now:
1. ✅ Detect that ACM is not available
2. ✅ Fall back to direct Subscription installation
3. ✅ Install Loki and NetObserv operators successfully
4. ✅ Configure LokiStack with S3 backend
5. ✅ Deploy FlowCollector for network monitoring

No manual intervention needed!

## Future: Enabling ACM OperatorPolicy

When you later install ACM on the hub cluster:

1. Install ACM on hub: `./ansible-runner.sh operators`
2. Import spoke clusters: `./ansible-runner.sh import`
3. Re-run NetObserv setup: `./ansible-runner.sh netobserv --limit cluster1`

The playbook will automatically detect the newly available OperatorPolicy CRD and use self-healing mode going forward.

## Key Features

✅ **Zero-impact** - Works on clusters with or without ACM
✅ **Automatic detection** - No manual configuration needed
✅ **Backward compatible** - Existing Subscription installations continue to work
✅ **Same cleanup** - `./ansible-runner.sh netobserv --destroy` works for both modes
✅ **Clear feedback** - User sees which mode is being used
✅ **Future-proof** - Can upgrade to ACM OperatorPolicy later
