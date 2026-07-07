# OpenShift Virtualization DR & Mobility

Ansible automation that stands up a three-cluster OpenShift 4.21 environment on AWS and
demonstrates **two hands-on ways to move a running Application/VM between regions** — plus a third,
lighter **VolSync direct-replication** DR pattern with a reference implementation:

| # | Use case | Mechanism | Recovery type |
|---|----------|-----------|---------------|
| 1 | **[Regional DR Failover](#use-case-1-test-regional-dr-failover)** | ODF Regional-DR (Ramen + VolSync) driven by an ACM `DRPlacementControl` | Disaster recovery — VM is **restarted** on the surviving cluster from replicated storage |
| 2 | **[Cross-Cluster Live Migration](#use-case-2-test-cross-cluster-live-migration-cclm-with-submariner)** | KubeVirt **decentralized live migration** over a **Submariner** pod network | Live mobility — VM **keeps running** while its memory + disk move to the other cluster |
| 3 | **[VolSync Direct DR](#use-case-3-lightweight-regional-dr-with-volsync-direct-cluster-to-cluster)** | VolSync `ReplicationSource`/`ReplicationDestination` (`rsync-tls` mover) replicating PVCs **directly cluster-to-cluster** — no ODF Ramen / MirrorPeer / DRPolicy | Lightweight disaster recovery — promote the replicated snapshot on the standby |

Everything runs inside a Podman container (no local Ansible needed) via `./ansible-runner.sh`.

## Topology

```
                 ┌──────────────────────────┐
                 │  cluster1  (HUB)          │   RHACM 2.17 + ODF Multicluster
                 │  ACM / GitOps / Ramen-hub │   Orchestrator + Ramen hub
                 └───────────┬──────────────┘
              manages / DRPolicy / Submariner broker
             ┌───────────────┴───────────────┐
   ┌─────────▼──────────┐          ┌──────────▼─────────┐
   │ cluster2 (SPOKE)   │◄────────►│ cluster3 (SPOKE)   │
   │ ODF 4.21 + CNV 4.21│ Submariner│ ODF 4.21 + CNV 4.21│
   │ pod 10.128.0.0/14  │  (direct  │ pod 10.132.0.0/14  │
   │ svc 172.30.0.0/16  │  pod mesh)│ svc 172.31.0.0/16  │
   └────────────────────┘          └────────────────────┘
```

- **Hub = cluster1**, **spokes = cluster2 / cluster3** (all AWS IPI, `us-east-2`, OpenShift **4.21**).
- Each cluster uses a separate AWS account via a named profile in `~/.aws/credentials`
  (set as `aws_profile` in `inventory/host_vars/<cluster>`).
- **The two spokes are installed with non-overlapping CIDRs** so Submariner runs **without
  globalnet** and routes pod-to-pod directly — a hard requirement for use case 2 (see below).

---

## Prerequisites

1. **Podman** on the host.
2. **`~/.aws/credentials`** with one named profile per cluster account, each with EC2/VPC/ELB/Route53/IAM permissions:
   ```ini
   [cluster1]
   aws_access_key_id = ...
   aws_secret_access_key = ...
   [cluster2]
   ...
   [cluster3]
   ...
   ```
   The profile each cluster uses is set by `aws_profile` in its `inventory/host_vars/` file.
3. **`pull-secret.json`** (Red Hat pull secret) and **`ssh-key.pub`** in the repo root.
4. A **public Route53 hosted zone** in each account (base domain is auto-detected).

Validate everything before deploying:

```bash
./ansible-runner.sh validate
```

---

## Common setup (both use cases)

Run these once to build the full environment. Total time ~2–3 h (three AWS cluster installs + operators + ODF + metal nodes).

```bash
./ansible-runner.sh deploy       # 1. Install cluster1/2/3 on OpenShift 4.21 (IPI)
./ansible-runner.sh operators    # 2. ACM + ODF MCO + Ramen-hub (hub); DR-cluster + OADP (spokes)
./ansible-runner.sh import       # 3. Import spokes into ACM as ManagedClusters
./ansible-runner.sh infra-dr     # 4. Submariner (globalnet OFF) + ODF StorageCluster on spokes
./ansible-runner.sh certs        # 5. cert-manager + Let's Encrypt wildcard certs on every ingress
```

> **Why `certs` matters for DR:** Ramen validates each `DRCluster` by reaching its ODF/Noobaa
> S3 endpoint over TLS. The `certs` step gives every `*.apps.<domain>` route (including the S3
> route) a publicly-trusted Let's Encrypt certificate, so `DRCluster … Validated=True` without
> any custom-CA trust plumbing. Skip it and Regional-DR replication stalls on TLS.

Confirm the DR control plane is healthy:

```bash
oc --kubeconfig artifacts/cluster1/kubeconfig get drpolicy,drcluster
# dr-policy   Validated=True ;  cluster2/cluster3  Validated=True
```

Then deploy OpenShift Virtualization and a VM on the spokes:

```bash
./ansible-runner.sh virt         # CNV 4.21 on both spokes (on m5.metal nodes) + DR-protected VM
```

`virt` provisions an `m5.metal` MachineSet on each spoke (bare metal is required for hardware
virtualization on AWS), installs CNV via an ACM policy, and deploys a DR-protected VM
`vm-dr-example` in namespace `vm-example`.

---

## Use case 1: Test Regional DR Failover

A DR-protected VM (`vm-dr-example`) runs on **cluster2**. Its disk is mirrored to **cluster3**
by ODF/VolSync, and an ACM `DRPlacementControl` (DRPC) governs where it runs. On a "regional
outage" you **fail it over** and Ramen restarts it on cluster3 from the replicated volume.

### 1. Confirm the VM is protected and running on cluster2

In the ACM console (**Fleet management → Search**, `kind:VirtualMachine`) the VM shows on **cluster2, Running**:

![VM running on cluster2 (ACM)](docs/images/regional-dr/01-acm-vm-on-cluster2.png)

Its DR state should be `Deployed` / `Protected=True` / `PeerReady=True`:

```bash
oc --kubeconfig artifacts/cluster1/kubeconfig \
   get drpc vm-dr-example-gitops-drpc -n openshift-gitops \
   -o jsonpath='{.status.phase} Protected={.status.conditions[?(@.type=="Protected")].status} PeerReady={.status.conditions[?(@.type=="PeerReady")].status}{"\n"}'
# Deployed  Protected=True  PeerReady=True
```

### 2. Fail over (or relocate) from the ACM console

The default way to move a DR-protected application is the RHACM **Fleet management → Applications**
view. The DR-protected app (`vm-dr-example-gitops-appset`) exposes **Failover application** and
**Relocate application** actions directly in its row menu:

![ACM Applications DR action menu — Failover / Relocate](docs/images/regional-dr-acm-ui/01-app-action-menu.png)

- **Failover application** — for an unplanned outage. Pick the target managed cluster (`cluster3`) in
  the modal; ACM sets the app's `DRPlacementControl` `action: Failover` and Ramen restarts the VM on
  cluster3 from the last replicated volume.
- **Relocate application** — for a planned, orderly move. Available once `PeerReady=True`; ACM sets
  `action: Relocate` to return the app to its preferred cluster (`cluster2`).
- **Manage disaster recovery** — opens the DR status (current placement, last-sync time, DRPolicy).

Watch it progress `FailingOver → FailedOver`, and the VM come up on cluster3:

```bash
watch 'oc --kubeconfig artifacts/cluster1/kubeconfig get drpc vm-dr-example-gitops-drpc -n openshift-gitops -o jsonpath="{.status.phase}"; \
       echo; oc --kubeconfig artifacts/cluster3/kubeconfig get vmi -n vm-example'
```

### 3. Verify the VM restarted on cluster3

ACM Search now shows the **same VM on cluster3, Running** (new instance, later timestamp) — and it is gone from cluster2:

![VM failed over to cluster3 (ACM)](docs/images/regional-dr/03-acm-vm-on-cluster3.png)

The OpenShift console on cluster3 shows the running VM:

![VM on cluster3 (console)](docs/images/regional-dr/04-cluster3-vm-running.png)

### Alternative: driving it from the CLI

The console actions are just a patch to the `DRPlacementControl` `spec.action`, so you can script the
same failover and fail-back:

```bash
# Fail over to cluster3 (unplanned outage)
oc --kubeconfig artifacts/cluster1/kubeconfig \
   patch drpc vm-dr-example-gitops-drpc -n openshift-gitops --type=merge \
   -p '{"spec":{"action":"Failover","failoverCluster":"cluster3"}}'

# Fail back once PeerReady=True (planned relocate to the preferred cluster)
oc --kubeconfig artifacts/cluster1/kubeconfig \
   patch drpc vm-dr-example-gitops-drpc -n openshift-gitops --type=merge \
   -p '{"spec":{"action":"Relocate","preferredCluster":"cluster2"}}'
```

> This is a **cold** move: the VM is stopped on the source and restarted on the target from
> replicated storage. Expect a reboot. That is by design — Regional DR is for site loss, not
> zero-downtime mobility. For zero-downtime, use case 2.

---

## Use case 2: Test Cross-Cluster Live Migration (CCLM) with Submariner

KubeVirt **decentralized live migration** moves a *running* VM from cluster2 to cluster3 with
no reboot. The VM's memory and disk stream directly between the two clusters' `virt-launcher`
pods, and a `virt-synchronization-controller` (TCP 9185, mTLS) coordinates the handoff. **All
of that traffic rides the Submariner pod network** — which is why the spokes must have
non-overlapping CIDRs and globalnet must be off (globalnet only routes exported Services, not
the ephemeral pod IPs the migration targets).

### Prerequisite: enable CCLM on both spokes

```bash
./ansible-runner.sh cclm
```

This enables the `decentralizedLiveMigration` feature gate on each spoke's HyperConverged (on CNV
4.22 it is on by default; on CNV 4.21 the play sets it as an HCO featureGate), waits for the
`virt-synchronization-controller`, and cross-imports each spoke's KubeVirt CA into the other's
`kubevirt-external-ca` for the mTLS sync channel.

Verify Submariner connects the spokes with **no globalnet**:

```bash
oc --kubeconfig artifacts/cluster2/kubeconfig get submariner -n submariner-operator \
   -o jsonpath='globalCIDR="{.items[0].spec.globalCIDR}"{"\n"}'   # empty = globalnet OFF
oc --kubeconfig artifacts/cluster1/kubeconfig get managedclusteraddon -A | grep submariner
# cluster2 submariner  Available=True ;  cluster3 submariner  Available=True
```

### 1. Live-migrate a running VM from the ACM console

The default way to drive a cross-cluster live migration is the RHACM **Fleet management** console. It
is orchestrated by **MTV (Migration Toolkit for Virtualization)** via the `cnv-mtv-integrations`
component. The spokes must be registered as MTV **providers** — the `virt` play labels the managed
clusters `acm/cnv-operator-install=true` for this; without it the console reports "cross-cluster live
migration is not possible".

In **Fleet management → Search** (`kind:VirtualMachine`), each VM row exposes a **Cross cluster
migration** action:

![ACM VM action menu with Cross cluster migration](docs/images/cclm-acm-ui/01-action-menu.png)

It opens the **Migrate VirtualMachines** wizard — pick the source/target cluster and project:

![ACM cross-cluster migration wizard](docs/images/cclm-acm-ui/02-wizard-open.png)

The **Migration readiness** step validates network mapping, storage mapping, and compute/version
compatibility, then creates and runs the MTV migration plan:

![ACM migration readiness — plan created](docs/images/cclm-acm-ui/05-migration-started.png)

Under the hood the console builds an MTV `Plan`/`StorageMap`/`NetworkMap` (`type: live`) that performs
the same KubeVirt decentralized live migration as the CLI (same `:9185` sync channel): CDI
**populates** the receiver disk (`PrepareTarget`), then the live state sync runs (`Synchronization`).
A healthy run reaches `Initialize → PrepareTarget → Synchronization = Completed` with the target VMI
`Running`. ACM Search then shows the VM **Running on the target cluster**:

![CCLM: VM running on target (ACM)](docs/images/cclm/01-cclm-vm-on-cluster3.png)

#### The receiver disk MUST be `volumeMode: Block`. Migration will fail otherwise.The automation makes `ocs-storagecluster-ceph-rbd-virtualization`
the **default virtualization StorageClass** on both spokes (`is-default-virt-class`, set by `infra-dr`),
and that class's `StorageProfile` defaults to **RWX / Block**. So VM disks are Block *and* the wizard's
`StorageMap` (which leaves `volumeMode` unset) inherits Block for the receiver — source and receiver are
byte-identical raw devices, and the migration completes.



> **To clear a hung/failed MTV migration:** delete the `plan`/`migration`/`storagemap`/`networkmap`
> in `mtv-integrations` and the leftover receiver `DataVolume` on the target spoke, then check the
> source VMI:
> ```bash
> oc --kubeconfig artifacts/cluster1/kubeconfig -n mtv-integrations delete migration,plan,storagemap,networkmap --all
> oc --kubeconfig artifacts/<target>/kubeconfig -n <ns> delete dv <vm>-disk   # removes the receiver PVC too
> oc --kubeconfig artifacts/<source>/kubeconfig -n <ns> get vmi <vm>          # expect Running; if Failed, delete it so the VM controller recreates it
> ```
> A Filesystem-receiver failure aborts *before* handoff, so the source VM keeps running; a failure
> mid-handoff can leave the source VMI `Failed` (the `runStrategy: Always` VM restarts it).

### Alternative: driving it from the CLI (`cclm-migrate`)

You can also drive the migration directly with KubeVirt CRs — **no ACM/MTV orchestration**. This is
lighter, leaves nothing to a wizard's storage mapping (it creates the receiver DataVolume without
forcing modes, so CDI inherits RWX Block from the `StorageProfile` automatically), and never disturbs
the source VM. Any running, PVC-backed VM works.

**1. Live-migrate cluster2 → cluster3** (demo VM `cclm-fedora` in `cclm-demo`):

```bash
./ansible-runner.sh cclm-migrate \
    -e cclm_vm=cclm-fedora -e cclm_from=cluster2 -e cclm_to=cluster3 -e cclm_vm_namespace=cclm-demo
```

Under the hood the play (`cclm-migrate.yml`):
1. Creates a receiver `VirtualMachine` (`runStrategy: WaitAsReceiver`) + blank DataVolumes on the target.
2. Creates a `receive` `VirtualMachineInstanceMigration` on the target and reads its
   `status.synchronizationAddresses[0]` — e.g. `10.132.0.32:9185`, a **raw cluster3 pod IP**
   reachable from cluster2 **only because Submariner routes the pod CIDR directly**.
3. Creates the matching `sendTo` migration on the source (`connectURL` = that address).
4. Waits for the target migration to reach `Succeeded`.

**2. Watch the VM move with zero downtime:**

```bash
watch 'echo cluster2:; oc --kubeconfig artifacts/cluster2/kubeconfig get vmi -n cclm-demo; \
       echo cluster3:; oc --kubeconfig artifacts/cluster3/kubeconfig get vmi -n cclm-demo'
# cluster3 VMI goes Scheduled → Running, then the cluster2 VMI disappears — the guest never rebooted.
```

**3. Migrate it back (bidirectional):**

```bash
./ansible-runner.sh cclm-migrate \
    -e cclm_vm=cclm-fedora -e cclm_from=cluster3 -e cclm_to=cluster2 -e cclm_vm_namespace=cclm-demo
```

ACM Search now shows the VM **Running on cluster2** again (the source side is left `Stopped`, as
decentralized migration intends):

![CCLM: VM back on cluster2 (ACM)](docs/images/cclm/02-cclm-vm-on-cluster2.png)

The OpenShift console on cluster2 shows the live VM:

![CCLM: VM on cluster2 (console)](docs/images/cclm/03-cclm-cluster2-console.png)

> This is a **live** move: the guest keeps running throughout. It requires L3 pod-to-pod
> reachability between the clusters (here, Submariner over non-overlapping CIDRs) plus mutual
> KubeVirt-CA trust — the two `VirtualMachineInstanceMigration` objects drive it directly.

---

## Use case 3: Lightweight Regional DR with VolSync (direct cluster-to-cluster)

Use case 1 leans on the **full ODF Regional-DR stack** — the ODF Multicluster Orchestrator, the Ramen
hub/cluster operators, a `MirrorPeer`, a `DRPolicy`, and a `DRPlacementControl` per app. That buys you
one-click, policy-driven failover, but it also requires ODF on both clusters and a fair amount of
moving parts.

When you want DR **without** that machinery — for example on SNO clusters, on non-ODF storage
(LVM/local/any CSI with snapshots), or a setup where you'd rather not run Ramen — you can drive
replication with **VolSync alone, syncing PVCs directly cluster-to-cluster** over `rsync-tls`. There is
no Ramen, no MirrorPeer, no `DRPlacementControl`: just a `ReplicationDestination` on the standby that
exposes an rsync endpoint, and a `ReplicationSource` on the primary that pushes to it on a schedule.

> 📎 **Reference implementation:** this project was inspired by
> **[MoOyeg/sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery)**, which implements
> exactly this VolSync-only pattern between two SNO clusters — ACM policies orchestrate the VolSync
> `ReplicationSource`/`ReplicationDestination`, OpenShift GitOps renders the app onto the *active*
> cluster, and **failover is a label flip on the hub** (`app-role=active/standby`) rather than a DRPC
> action. The rsync endpoint is published with **MetalLB** (a `LoadBalancer` Service), and **Submariner**
> provides cross-cluster reachability when the two clusters aren't on shared subnets.

### How it works

```
   cluster2 (primary)                                   cluster3 (standby)
   ┌────────────────────┐        rsync-tls stream       ┌────────────────────┐
   │ app PVC            │   over LoadBalancer / Submariner │ ReplicationDest    │
   │ ReplicationSource  │ ───────────────────────────►  │  → VolumeSnapshot   │
   │  (every 5 min)     │      (direct, no object store) │  (latestImage)      │
   └────────────────────┘                               └────────────────────┘
                                                          promote snap → PVC on failover
```

- The **`ReplicationDestination`** on the standby (rsync-tls mover) creates a Service exposing the
  rsync endpoint plus a pre-shared TLS key; its `.status.rsyncTLS.address` is where the source connects.
- The **`ReplicationSource`** on the primary snapshots the app PVC and syncs it to that address on a
  schedule — the schedule *is* your RPO (e.g. 5 minutes).
- Each sync lands on the standby as a `VolumeSnapshot` (`.status.latestImage`), ready to be promoted to
  a PVC on failover.
- The data path is **cluster → cluster** (no object storage in the middle): the source must reach the
  destination's rsync Service, published via a **LoadBalancer** (MetalLB on-prem / a cloud ELB) or made
  routable with **Submariner**. Storage is anything with CSI snapshots — Ceph, LVM, local, etc.

### Sketch of the CRs

```yaml
# On the STANDBY — expose an rsync-tls endpoint and land each sync as a snapshot
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata: { name: app-data, namespace: my-app }
spec:
  rsyncTLS:
    serviceType: LoadBalancer      # MetalLB / cloud LB address the source dials
    copyMethod: Snapshot
    accessModes: [ReadWriteOnce]
    capacity: 10Gi
# -> .status.rsyncTLS.address (endpoint) + a generated pre-shared key Secret to hand to the source
---
# On the PRIMARY — sync the app PVC to the standby every 5 minutes
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata: { name: app-data, namespace: my-app }
spec:
  sourcePVC: app-data
  trigger: { schedule: "*/5 * * * *" }        # RPO = 5 min
  rsyncTLS:
    address: <ReplicationDestination .status.rsyncTLS.address>
    keySecret: volsync-rsync-tls-app-data     # the pre-shared key from the destination
    copyMethod: Snapshot
```

### Failover / failback

1. **Fail over:** stop the `ReplicationSource` on the (lost) primary, promote the standby's
   `ReplicationDestination.status.latestImage` snapshot into the app PVC, and start the app on the
   standby. With the linked repo's model this is a single **label flip** on the hub — ACM policies swap
   the VolSync roles and GitOps re-renders the app onto the new active cluster.
2. **Fail back:** reverse the roles (old standby becomes the source), and flip the label back once the
   volumes are caught up.

> Compared to use case 1 this trades one-click, sub-second-RPO storage mirroring for a **simpler,
> storage-agnostic** replicate-and-restore DR: no ODF Regional-DR operators, coarser RTO
> (promote-from-snapshot), and RPO bounded by the sync schedule. It still needs a network path for the
> rsync stream (a LoadBalancer or Submariner), but no Ceph/ODF and no Ramen.

---

## Command reference

| Command | Purpose |
|---------|---------|
| `./ansible-runner.sh deploy` | Install cluster(s) on AWS (IPI, OpenShift 4.21) |
| `./ansible-runner.sh destroy --yes` | Tear down cluster(s) |
| `./ansible-runner.sh operators` | ACM + ODF MCO + Ramen (hub); DR-cluster + OADP (spokes) |
| `./ansible-runner.sh import` | Import spokes into ACM |
| `./ansible-runner.sh infra-dr` | Submariner (globalnet off) + ODF StorageCluster |
| `./ansible-runner.sh certs` | cert-manager + Let's Encrypt wildcard certs |
| `./ansible-runner.sh app` | MirrorPeer + DRPolicy + sample DR app |
| `./ansible-runner.sh virt` | OpenShift Virtualization + DR-protected VM |
| `./ansible-runner.sh cclm` | Enable cross-cluster live migration on the spokes |
| `./ansible-runner.sh cclm-migrate -e cclm_vm=… -e cclm_from=… -e cclm_to=…` | Live-migrate a VM between spokes |
| `./ansible-runner.sh validate` / `list` / `shell` | Validate config / list clusters / debug shell |

Add `--destroy` to `operators`, `infra-dr`, `certs`, `app`, `virt`, `cclm` to remove what they created.

## Key configuration

- `inventory/group_vars/all.yml` — OpenShift version (`4.21`), operator channels
  (ACM `release-2.17`, ODF `stable-4.21`), `globalnet_enabled: false`.
- `inventory/host_vars/cluster{1,2,3}` — per-cluster `aws_profile`, region, and the
  **non-overlapping** `cluster_network_cidr` / `service_network_cidr` / `machine_network_cidr`
  that make Submariner-without-globalnet (and therefore CCLM) possible.

## Notes / gotchas

- **Non-overlapping CIDRs are load-bearing for use case 2.** If the spokes share CIDRs you must
  run Submariner with globalnet, and CCLM's pod-to-pod data path will not route. Changing CIDRs
  means reinstalling the spoke.
- **`certs` before Regional-DR replication.** Let's Encrypt certs on the S3 routes are what let
  Ramen validate the `DRCluster`s over TLS.
- **ODF Multicluster Orchestrator needs GitOps.** On the hub, the ArgoCD (`argoproj.io`) CRDs
  must exist before the ODF MCO subscription, or `odfmo-controller-manager` crash-loops; the
  `operators` play installs OpenShift GitOps first for this reason.
- Inspired by [sno-disaster-recovery](https://github.com/MoOyeg/sno-disaster-recovery).
