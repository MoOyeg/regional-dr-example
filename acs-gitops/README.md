# ACS Policy as Code Demo

Demonstrates the [Managing policies as code](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.10/html-single/operating/index#policy-as-code-create-portal_managing-policies-as-code)
workflow from the Red Hat Advanced Cluster Security for Kubernetes 4.10
documentation: ACS policies are authored as `SecurityPolicy` Custom Resources
(`config.stackrox.io/v1alpha1`), committed to Git, and applied to the
`stackrox` namespace by ArgoCD. Central's `config-controller` reconciles the
CRs into live policies — no clicking through the UI to keep environments in
sync.

Wire it up with:

    ./ansible-runner.sh acs-gitops

## Authoring a policy

Per the docs there are two supported workflows. Either is fine; pick whichever
fits the policy you're writing.

1. **Clone-and-export from Central.** Open *Policy Management*, clone an
   existing default policy (you must clone — defaults can't be exported
   directly), edit it, then in the row's overflow menu pick
   *Save as Custom Resource*. Bulk export is also available via
   *Bulk actions → Save as Custom Resources*. Drop the resulting YAML in
   this directory and push.
2. **Hand-write the CR.** Use the skeleton:

   ```yaml
   apiVersion: config.stackrox.io/v1alpha1
   kind: SecurityPolicy
   metadata:
     name: short-name
   spec:
     policyName: A longer form name
     # ...
   ```

   Run `oc explain securitypolicy.spec` to discover the available fields.

## What's in this directory

Top-level — three policies that double as the walkthrough:

- [`securitypolicy-no-latest-tag.yaml`](securitypolicy-no-latest-tag.yaml) —
  hand-written CR that flags deployments using the `:latest` image tag.
- [`securitypolicy-no-privileged.yaml`](securitypolicy-no-privileged.yaml) —
  hand-written CR that flags privileged containers.
- [`securitypolicy-required-image-label.yaml`](securitypolicy-required-image-label.yaml) —
  example "cloned-from-default" CR requiring a `maintainer` image label.

[`samples/`](samples/) — a library of additional inform-mode SecurityPolicies
(no `enforcementActions` set, so Central alerts but doesn't block). ArgoCD
recurses into the directory and applies them all. See
[`samples/README.md`](samples/README.md) for the full list and how to switch
any of them into enforce mode.

## Editing

Change a YAML file, commit, push. ArgoCD's automated sync (with self-heal and
prune enabled) reapplies the CR within a couple of minutes; `config-controller`
on Central then reconciles it into a live policy.

> **Policy drift:** if someone edits one of these policies in the Central UI,
> the next ArgoCD sync (or any direct `oc apply`) will overwrite their changes
> back to whatever is in Git. Treat Git as the source of truth, or disable
> policy-as-code on the Central CR
> (`spec.configAsCode.configAsCodeComponent: Disabled`) if that's not what you
> want.

## Removing

    ./ansible-runner.sh acs-gitops --destroy

Deletes the ArgoCD Application; `prune=true` removes the synced
`SecurityPolicy` CRs, and `config-controller` removes the corresponding live
policies from Central.
