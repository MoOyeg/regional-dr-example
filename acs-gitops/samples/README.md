# Sample SecurityPolicies (inform mode)

A library of `SecurityPolicy` CRs (`config.stackrox.io/v1alpha1`) that ArgoCD
syncs into the `stackrox` namespace alongside the top-level demo policies.
Every sample here is **inform-only**: none of them set
`spec.enforcementActions`, so Central will raise violations and surface them in
the Violations view but won't block builds, deploys, or runtime.

To switch any of these to enforce mode, add an `enforcementActions` list to the
`spec`, e.g.:

```yaml
spec:
  # ...
  enforcementActions:
    - SCALE_TO_ZERO_ENFORCEMENT          # DEPLOY  stage
    - UNSATISFIABLE_NODE_CONSTRAINT_ENFORCEMENT
    - FAIL_BUILD_ENFORCEMENT             # BUILD   stage
    - KILL_POD_ENFORCEMENT               # RUNTIME stage
```

## What's here

| File | Severity | Stage | Flags |
| --- | --- | --- | --- |
| [`no-sys-admin.yaml`](no-sys-admin.yaml) | HIGH | DEPLOY | containers requesting `CAP_SYS_ADMIN` |
| [`no-host-network.yaml`](no-host-network.yaml) | HIGH | DEPLOY | pods using `hostNetwork: true` |
| [`no-host-pid.yaml`](no-host-pid.yaml) | HIGH | DEPLOY | pods using `hostPID: true` |
| [`readonly-root-fs.yaml`](readonly-root-fs.yaml) | MEDIUM | DEPLOY | containers with a writable root filesystem |
| [`stale-image-scan.yaml`](stale-image-scan.yaml) | MEDIUM | DEPLOY | images last scanned more than 30 days ago |
| [`fixable-important.yaml`](fixable-important.yaml) | HIGH | DEPLOY | deployments with fixable Important+ CVEs |
