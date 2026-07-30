# CLAUDE.md - Project Intelligence

## Project Overview
- Ansible-based automation for deploying OpenShift SNO clusters across multiple AWS regions
- Inspired by [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery)
- Everything runs inside a Podman container (no local Ansible needed)

## Key Architecture Decisions
- **ansible-runner.sh** follows the pattern from `ansible-devstack-kvm`: simple shell wrapper that builds container image and delegates to `run_ansible()` function
- Two deployment modes: IPI (installer creates infra) and UPI (existing VPC/subnet)
- Up to 3 AWS credential sets via numbered env vars (`AWS_ACCESS_KEY_ID_1`, `_2`, `_3`)
- All Ansible tasks use `delegate_to: localhost` — clusters are inventory "hosts" but everything runs locally via AWS API
- **SSH key management**: Two options for UPI mode — local `ssh-key.pub` auto-imported to EC2 as `<cluster_name>-key`, or pre-existing AWS EC2 key pair via `aws_key_name`. Imported keys are cleaned up on destroy.

## File Structure
- `ansible-runner.sh` — Main entrypoint (build, deploy, destroy, validate, list, run, shell)
- `deploy-clusters.yml` — Core deployment playbook (IPI + UPI modes)
- `destroy-clusters.yml` — Teardown playbook (supports `force_destroy` extra var for --yes flag)
- `validate.yml` — Pre-flight credential/config checks
- `inventory/hosts` — Cluster inventory under `[openshift_clusters]` group
- `inventory/group_vars/all.yml` — Global defaults (OpenShift 4.22.5, m5.2xlarge, 120GB)
- `inventory/host_vars/` — Per-cluster configs (aws_credential_set, region, VPC, AMI, etc.)
- `templates/install-config.yaml.j2` — SNO install-config (1 master, 0 workers, OVNKubernetes)
- `Containerfile` — UBI9-based image with Ansible, AWS CLI, oc, openshift-install
- `setup-oadp.yml` / `oadp-backup.yml` / `oadp-restore.yml` — OADP VM backup/restore to an S3 bucket
  (CSI snapshot + data mover, since VM disks are Block); commands `oadp` / `oadp-backup` / `oadp-restore` (use case 4)
- `destroy-oadp.yml` — `oadp --destroy`. Play 1 (hub) removes both policy files' Policies/Placements/
  Bindings **first** (they are `enforce`, so a surviving spoke policy re-creates the Schedule or
  re-restores the VM mid-teardown), then `oadp-dr-config`/`oadp-dr-status`, the `oadp-failover-timer`
  Pod, the `oadp-vm-view` MCVs and the `oadp-role` labels. Play 2 (spokes) deletes the Velero
  Schedules/Backups/Restores (fully-qualified `*.velero.io`), the DPA + `cloud-credentials`, the two
  labels setup added (`velero.io/csi-volumesnapshot-class`, `oadp-backup`) and the `vm-example-oadp`
  namespace (`oadp_remove_demo_vm=false` keeps it). Play 3 deletes the S3 bucket only with
  `-e oadp_remove_bucket=true` — it holds the backups, so the default is to keep it. The OADP
  **operator** is out of scope: `operators --destroy` owns it.
- `acm-policy-oadp-schedule.yaml` — ACM policy (applied by `oadp`, Play 3) that watches VMs for the
  `oadp-backup` label and creates a Velero `Schedule` (the OADP "backup cronjob": */5, 1h TTL) per
  labelled VM, pruned when unlabelled; a second inform policy confirms backups are produced (use case 4).
  The Schedule's `template.metadata.labels` stamp `oadp-backup-vm`/`-namespace` onto every Backup it
  produces, which is how the auto-restore policy attributes a backup in the shared bucket to a VM.
- `acm-policy-oadp-autorestore.yaml` — **OADP auto-failover** (use case 4, also applied by `oadp`).
  Keyed on the **`oadp-role: active/standby`** ManagedCluster label (dedicated; independent of use
  case 3's `app-role` and use case 5's `pg-role`). Three policies: `oadp-vm-autofailover-hub`
  (local-cluster: `ManagedClusterView` of the VM per spoke, grace-period timer, `oadp-dr-status`
  ConfigMap, flips the labels), `oadp-vm-restore-active` (active spoke: restores the newest
  Completed/PartiallyFailed backup when the VM is missing **and** the hub says `restoreOnActive`,
  starts a VM carrying `velero.io/restore-name`, un-pauses its Schedule), `oadp-vm-standby-cleanup`
  (standby: pauses the Schedule, drops the stale VM + the PVCs it references once the active site is
  up — required, since Velero will not re-hydrate an existing PVC). Failover is automatic; failback is
  a manual `oadp-role` label flip. Inputs: hub `oadp-dr-config` ConfigMap written by setup-oadp.yml
  from group_vars (`oadp_dr_vm_name`, `oadp_failover_grace_seconds`, `oadp_standby_cleanup`, …).
  The protected VM is its OWN copy in `vm-example-oadp` (`vm-app-oadp/`, applied straight to the
  active spoke by `oadp`, deliberately NOT via GitOps) — `vm-example` is Ramen-protected and
  ArgoCD-synced, so an OADP failover there would be undone by GitOps and fight Ramen. Same split as
  use case 3's `vm-example-volsync`.
  **Gotchas (all found live):**
    - The 30s dwell is a hub **`Pod`** (not a Job) running `sleep 30`. ACM's sprig allowlist has no
      date arithmetic (don't reach for `now`/`toDate`), so the timer has to be an object — and it must
      be a *named* one: deleting a `batch/v1` Job orphans its pods, and a ConfigurationPolicy
      `mustnothave` with labels but no name is **reported as a violation and never deleted**, which
      pinned the policy NonCompliant forever.
    - A `ManagedClusterView` keeps its last result when a fetch fails, so "VM gone" is detected by a
      **False condition** on the view, not by an absent `status.result`.
    - `oadp-dr-status` is **one evaluation cycle stale after a role flip** — the placement moves the
      spoke policies before the hub rewrites it. The standby cleanup must check `activeSite` names a
      *different* cluster before trusting `vmAvailable`, or it deletes its own running VM and causes a
      genuine failover ping-pong.
    - The new active's `Schedule` is created when the VM *object* lands, minutes before the data mover
      finishes; left unpaused it backs up a half-written disk that then outranks the good backup. The
      active-site policy pauses it until `status.ready`.
    - Standby cleanup must delete leftover **PVCs even when no VM object remains** — Velero does not
      re-hydrate an existing PVC (`existingResourcePolicy` only updates metadata).
    - Backups of this VM are always `PartiallyFailed` (KubeVirt freeze hook, no guest agent), so the
      restore side must accept that phase; and `WaitingForPluginOperationsPartiallyFailed` is a real
      in-flight phase — match phases with `eq`, never a substring test.
  **VALIDATED LIVE 2026-07-27**: failover ~75s to the role flip, ~4 min to VM Running on the peer;
  failback by label flip keeps the old site serving for 225s of 232s; 10GB disk round-tripped
  byte-identical through S3; all four policies Compliant.
- `setup-volsync-dr.yml` / `destroy-volsync-dr.yml` (app) + `-vm` variants — VolSync Direct DR (use case 3),
  ported/adapted from MoOyeg/sno-disaster-recovery. ACM-policy engine (`acm-policy-volsync-automate.yaml`
  app / `acm-policy-volsync-vm.yaml` VM) keyed on the `app-role: active/standby` ManagedCluster label;
  failover = flip the label on the hub. Runs in dedicated `*-volsync` namespaces (manifests under
  `app-volsync/` + `vm-app-volsync/`) so it coexists with the Ramen-based use case 1. Command `volsync-dr`
  (`--vm`, `--destroy`). Images in `docs/images/volsync-dr/`.
- `setup-rhsi.yml` / `destroy-rhsi.yml` — **CNPG cross-site Postgres over Red Hat Service Interconnect**
  (Skupper v2). Command `rhsi` (use case 5). REWRITTEN 2026-07 from the old VM-bridging demo (which was
  live-validated but is now retired). Installs `skupper-operator`
  + Network Observer (AllNamespaces, asserted) **and** the CloudNativePG operator on each spoke; a Site +
  mTLS Link in `postgres-dr`; side-loads a **shared CA + `streaming_replica` cert** to both spokes; deploys
  the `pg-app` sample (`app-cnpg/`, writes a heartbeat via the `pg-write` VAN key, reads the local `pg-r`).
  The ACM policy engine (`templates/rhsi-cnpg-policy.yaml.j2`, rendered NOT inline) is keyed on the
  **`pg-role: active/standby`** ManagedCluster label (dedicated label, independent of use case 3's
  `app-role`; reuses the `dr-clusters` clusterset + `open-cluster-management-global-set` policy ns):
    - `cnpg-fabric` (both spokes): the CNPG `Cluster pg` (**distributed topology**, CNPG ≥ 1.24;
      `spec.replica.self/primary/source`) — role set by a **hub template** reading which spoke is
      `pg-role=active`; the Cluster is **never pruned** (owns data) — plus a `pg-write` Skupper Listener.
    - `cnpg-connector` (active spoke): a `pg-write` Connector → local primary (`cnpg.io/instanceRole=primary`);
      pruned on failover so the write path follows.
    - `cnpg-hub-relay` (local-cluster): `ManagedClusterView` per spoke → hub `cnpg-dr-config` ConfigMap
      (`activeSite`/`currentPrimary`/`promotionToken`) — carries CNPG's `demotionToken` old→new primary.
  Failover = flip `pg-role` on the hub → **controlled switchover** (demotionToken→promotionToken relay,
  zero data loss); manual fallback `oc cnpg promote pg -n postgres-dr`.
  **Gotchas:** streaming uses `sslmode: verify-ca` (verify-full fails — the replica dials the Listener DNS
  `pg-write`, not in the server-cert SAN); the `.j2` wraps all hub/Go templates in Jinja `raw`/`endraw`
  and **closing `endraw` must be at column 0** (a 12-space-indented `endraw` welds its leading spaces onto
  the next `---` and eats the document separator); Listener/Connector ports are plain Ansible-injected
  ints — but **CNPG `connectionParameters` ports must be QUOTED strings** (it is `map[string]string`),
  opposite rules in one file. Also: the `.j2` **header is outside the raw block**, so it must contain no
  Jinja delimiters at all.
  **RE-VALIDATED 2026-07-30** on a rebuilt environment with all FIVE use cases running side by side:
  switchover completed **unaided in 50s** from the label flip, the pre-switchover row survived, a fresh
  write on the new primary replicated **back** to the demoted site, and the `pg-write` Connector
  followed. A SIXTH defect was found and fixed first: replication dialled the shared `pg-write` key,
  but during handover BOTH pods still carry `cnpg.io/instanceRole=primary`, so the promoting site's own
  Connector matched its own replica and Skupper local-preference made it **stream from itself** -
  `receive_lsn` frozen short of the promotion token's LSN, token never verified, BOTH sites left as
  replicas with no writable database, indefinitely. `pg_stat_wal_receiver` said `streaming` the whole
  time. Fix: **site-scoped routing keys** (`pg-site-<site>`, one Connector per site with a role-agnostic
  selector, `externalClusters` host `pg-<site>`), so there is no local target to shadow the peer.
  **VALIDATED LIVE 2026-07-27** (Sites+Link Ready, CNPG streaming over the VAN, `pg-role` flip =
  controlled switchover with zero data loss, write path followed). Five defects found live:
    - `cloudnative-pg` is in the **certified-operators** catalog, NOT community.
    - **A hub template may not list cluster-scoped resources**: `lookup … "ManagedCluster" "" ""` fails
      ("lookup of cluster-scoped resource 'ManagedCluster/' is not allowed") and a hub template that
      fails to render means ACM **never creates that ConfigurationPolicy on the spoke at all** — the
      error is buried in the REPLICATED policy's status in the cluster namespace, not on the root
      policy and with no event. Read `activeSite` from the `cnpg-dr-config` ConfigMap instead
      (namespaced lookups in the policy's own namespace ARE allowed). Same lookup is fine in
      `cnpg-hub-relay` — that runs as a normal managed-cluster template on local-cluster.
    - **CNPG bring-your-own CA must be an ECDSA key in SEC1 PEM** (`BEGIN EC PRIVATE KEY`): it parses
      user CAs with `ParseECPrivateKey`. A valid RSA/PKCS#8 CA yields `generating server TLS
      certificate: invalid private key PEM block type`. Use `openssl ecparam -genkey -noout`;
      `openssl genpkey -algorithm EC` emits PKCS#8 and fails the same way.
    - **`spec.bootstrap` is immutable** — render it from the SITE, never the current role, or every
      switchover rewrites it, the API rejects the whole update (including `replica.primary`), and the
      switchover deadlocks on "cannot be updated, likely due to immutable fields not matching".
    - setup-rhsi.yml re-labelled `pg-role` on every run and silently reverted an in-progress
      switchover; roles are now seeded once (same pattern as setup-oadp.yml).

## Development Conventions
- **Architecture diagrams**: `docs/diagrams/gen_diagrams.py` emits one `.drawio.svg` per use case into
  `docs/images/diagrams/` (embedded in the README). Each file is BOTH a GitHub-rendered SVG and an
  editable draw.io model (mxGraph XML in the SVG `content` attr) — edit the Python spec (source of truth)
  and re-run `python3 docs/diagrams/gen_diagrams.py`, or edit the `.drawio.svg` in diagrams.net. Validate
  with jinja/yaml — the SVG must stay well-formed and the embedded `content` XML parseable.
- **ACM policy templates**: `object-templates-raw` is a Go template that renders YAML, so it can be
  checked without a cluster — extract each `object-templates-raw`, stub `lookup`/`default`/`list` +
  the `{{hub … hub}}` pass, render with Go's `text/template` against a fake cluster state, and
  YAML-parse the result. Worth doing for anything with branching; it catches what YAML linting can't.
  Two gotchas it flushed out: a comment must close as `*/}}` or `*/ -}}` (Go rejects `*/ }}` with
  "comment ends before closing delimiter"), and `{{- /* … */ -}}` between two emitted objects eats the
  newline and **welds the next `- complianceType:` onto the previous line** — use `{{- /* … */}}`
  wherever a comment sits between rendered YAML blocks.
- Shell scripts: 3 color functions (print_info/warn/error), no emojis in output
- Containerfile: `ansible>=2.14` version pin, `ENTRYPOINT ["ansible-playbook"]`, `CMD ["--version"]`
- ansible.cfg: yaml stdout callback, profile_tasks+timer callbacks, jsonfile fact caching
- setup.sh delegates to `./ansible-runner.sh build` — does not inline build logic

## Common Commands
```bash
./ansible-runner.sh build                          # Build container image
./ansible-runner.sh deploy                         # Deploy all clusters
./ansible-runner.sh deploy --limit cluster1 -v     # Deploy specific cluster
./ansible-runner.sh destroy --yes                  # Destroy all clusters
./ansible-runner.sh validate                       # Validate config
./ansible-runner.sh shell                          # Debug shell in container
```

## SSH Key Management
- `ssh-key.pub` — Public key used in OpenShift install-config and optionally imported to EC2
- `ssh-key` — Private key (optional), mounted into container by ansible-runner.sh for direct SSH access to nodes
- If `aws_key_name` is not set in host_vars, deploy playbook auto-imports `ssh-key.pub` as EC2 key pair `<cluster_name>-key`
- Imported key pairs are tagged with `managed-by=ansible` and deleted during `destroy`

## Minimal Infrastructure Deploy
- `deploy --minimal` / `infra-dr --minimal` passes `-e minimal_infra=true` (default `false`)
- Forces every cluster to SNO (1 master / 0 workers) with role-specific instance types
  (`minimal_hub_instance_type` = large VM for hub, `minimal_spoke_instance_type` = `.metal` for
  spokes — bare metal is required for KVM/OpenShift Virtualization on AWS). Override in group_vars.
- Topology override happens at deploy time in `deploy-clusters.yml` pre_tasks (doesn't touch host_vars)
- Submariner: `setup-submariner.yml` labels the spoke's single node `submariner.io/gateway=true` and
  omits the dedicated-gateway `gatewayConfig.aws` block, so the SNO node IS the gateway (no extra machine)
- ODF single-node: `infra-dr.yml` sets `flexibleScaling: true` + device set `replica: 1` /
  `count: {{ odf_minimal_device_set_count }}` (3 OSDs on the one host, failure domain host, not HA)
- Hub SNO defaults to `m5.8xlarge` (`minimal_hub_instance_type`) to fit the full hub stack

## Known Issues / Gotchas
- **Deleting a Ramen-managed object directly on a spoke does NOT self-heal.** The hub's ManifestWork
  still believes the resource is applied, so nothing re-pushes it and the DRPC sits at
  `Missing VolumeReplicationGroup status from cluster <spoke>` forever. Recovery goes through the HUB:
  `oc delete manifestwork <drpc>-<ns>-vrg-mw -n <spoke>` — Ramen recreates it and re-derives
  protection cleanly (a fresh `vr-<uuid>` appears, not the old name). Nudging the VRG with an
  annotation does nothing; Ramen reconciles, logs `Requeue:false`, and stops. Cost ~15 min on
  2026-07-30.
- **A DRPC can stall at `Protected=False` because ONE PVC got claimed by both replication schemes.**
  csi-addons then refuses it: `PVC (<ns>/<pvc>) can't be owned by both VolumeReplication and
  VolumeGroupReplication`, the VolumeGroupReplicationContent never gets a handle, and `DataReady`
  never flips. Ramen creates the per-PVC VR first and the group VGR ~14s later without removing the
  first. NOTE both objects coexisting is NORMAL when a namespace has several PVCs (vm-example runs
  VR + VGR happily) — the fault is one PVC owned twice. Do NOT delete the VolumeReplication (that
  removes the half actually replicating and leaves Ramen with nothing to reconcile); recreate the VRG
  via the hub ManifestWork instead.
- **RBD consistency groups are MIRRORED — never `rbd group rm` to unstick a DRPC.** Deleting the group
  on the primary destroys the peer's copy, and the peer's promote then fails with `failed to get
  volume group by id ...`, stranding an in-flight failover with no writable site. `rbd group image rm`
  is refused outright (`cannot remove image from mirror enabled group`). If a group membership really
  is orphaned, recreate the PVC instead.
- **`oc get backup` is ambiguous and the winner changes as you install use cases.** It resolved to
  `backups.postgresql.cnpg.noobaa.io` with ODF, and once use case 5 installs CNPG it resolves to
  `backups.postgresql.cnpg.io` — so `oadp-backup`/`oadp-restore` started reporting "not found" for a
  Velero backup that existed and had completed. **Installing use case 5 broke use case 4's playbooks.**
  Always `backups.velero.io` / `restores.velero.io` / `schedules.velero.io` in full, in playbooks as
  well as docs (fixed in oadp-backup.yml + oadp-restore.yml).
- **`failed_when` REPLACES the default rc/retry failure.** A task with `until` + `failed_when` that
  exhausts all its retries — or whose command errors every single time — is still reported `ok`, and
  the play carries on. That masked the bug above until it surfaced two tasks later somewhere unrelated.
  Both OADP playbooks now assert the terminal phase in a separate task.
- **Backups of a running VM are `PartiallyFailed`, and that is restorable.** OADP's KubeVirt freeze
  hook fails without a guest agent; the disk data is still fully moved. Anything that waits for
  `Completed` alone (oadp-restore.yml did) can never restore a VM backup. Also note
  `WaitingForPluginOperationsPartiallyFailed` is a real *non-terminal* phase — match phases exactly,
  never by substring.
- **infra-dr on a single-AZ cluster**: ODF picks `failureDomain: rack` and hands every storage-labelled
  node a rack. The Submariner addon's dedicated gateway node carries `infra,worker` roles, so a bare
  `-l node-role.kubernetes.io/worker=` selector labelled it as storage, it was given a rack, and the
  mon that had to land in that rack could never schedule (the node is tainted
  `node-role.submariner.io/gateway`) — StorageCluster stuck `Progressing` forever. The selector now
  excludes infra nodes. If you ever fix racks by hand, note the relabel moves OSDs: safe here only
  because every node is in one AZ, so the EBS volume can re-attach.
- **infra-dr ODF waits**: `grep -i ocs` also matches `ocs-client-operator`, and the test is only
  "is Succeeded anywhere in the output" — so it passed before `ocs-operator` registered the
  StorageCluster CRD. Anchored to `^ocs-operator\.` plus an explicit CRD wait.
- **`ocs-storagecluster-ceph-rbd-virtualization` cannot exist before `virt` runs** — ODF only creates
  it once CNV is installed. infra-dr's wait for it is best-effort; `setup-virt.yml` Play 5 owns the
  `is-default-virt-class` annotation.
- **`virt` Play 6 needs a Ramen `DRPolicy`**, which `deploy-app.yml` (`app`) creates — but the README's
  common setup runs `virt` straight after `infra-dr`/`certs` and never mentions `app`. Plays 1-5
  (metal MachineSet + CNV + storage class) complete fine; only the DR-protected-VM plays fail.
- **`ansible-runner.sh` rebuilds the image every command**, so podman images pile up — 706 images /
  68GB reclaimable filled the 200GB root filesystem and broke a run with
  `[Errno 28] No space left on device`. `podman image prune -f` (dangling only; **not** `-a`, which
  would eat locally-built operator bundles) reclaimed 55GB.
- `secret.sh` contains plaintext AWS credentials and is NOT gitignored — rotate keys and add to .gitignore
- The `destroy` command supports `--yes`/`-y` flag which passes `-e force_destroy=true` to the playbook
- install-config.yaml.j2 is SNO-specific: `bootstrapInPlace` with `/dev/xvda` (UPI only; IPI SNO omits it)
