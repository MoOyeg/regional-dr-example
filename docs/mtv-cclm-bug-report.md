# Bug: MTV cross-cluster live migration fails when the receiver disk cannot hold the source's raw Block device

## Component
Migration Toolkit for Virtualization (forklift) + `cnv-mtv-integrations` ACM component, cross-cluster
**live** migration of a running KubeVirt VM (`Plan.spec.type: live`).

## Environment
- OpenShift 4.22.2, OpenShift Virtualization (CNV) 4.22, ODF 4.21, RHACM 2.17, MTV/forklift via
  `cnv-mtv-integrations`, Submariner (globalnet off, non-overlapping cluster CIDRs).
- Source VM disk: StorageClass `ocs-storagecluster-ceph-rbd-virtualization`, `ReadWriteMany`,
  `volumeMode: Block`, 30Gi = **32212254720 bytes** (raw RBD device).
- Migration pipeline: `Initialize → PrepareTarget` (CDI populates the receiver PVC) `→ Synchronization`
  (KubeVirt decentralized live migration, control channel TCP `:9185`).

## Summary
The MTV live-migration path provisions the receiver PVC from a `StorageMap` that **does not pin
`destination.volumeMode`**. The receiver's volume mode is therefore whatever the destination
StorageClass's `StorageProfile` defaults to. KubeVirt live migration mirrors the source's **raw Block
device byte-for-byte**, so the receiver must expose **≥ 32212254720 usable bytes**. A `Filesystem`
receiver cannot: a 30Gi Filesystem PVC's backing `disk.img` is only **31589400576 bytes** (~29.42 GiB)
after filesystem + CDI overhead (~594 MiB short). There is no pre-flight guard for this, so the
migration fails at the target `qemu` with a confusing error and can leave the source VMI `Failed`.

## Deterministic reproduction
1. Running VM with an `ocs-storagecluster-ceph-rbd-virtualization` RWX/Block 30Gi disk on spoke A.
2. Create an MTV `Plan` (`type: live`) A→B with a `StorageMap` whose destination sets
   `volumeMode: Filesystem` (or maps to a StorageClass whose StorageProfile defaults to Filesystem).
3. Start the `Migration`. The receiver PVC binds as `Filesystem` 30Gi and the target `virt-launcher`
   `qemu-kvm` fails to start:
   ```
   qemu-kvm: -blockdev {"driver":"raw","file":"libvirt-1-storage","offset":0,
   "size":32212254720,...,"cache":{"direct":true,"no-flush":false}}:
   The sum of offset (0) and size (32212254720) has to be smaller or equal to
   the actual size of the containing file (31589400576)
   ```
   Plan → Failed. (Observed variant with a mid-transfer receiver: source VMI `migrationState`
   `failureReason: virError(Code=9, ...'migration of disk vda failed: Input/output error')`,
   which then leaves the source VMI `Failed` / VM `Stopped`.)

## Contrast — the same plan with a Block receiver SUCCEEDS
Identical `Plan`/`NetworkMap`; `StorageMap` maps `ceph-rbd-virtualization → ceph-rbd-virtualization`
with **no `volumeMode` override** (so it inherits the StorageProfile default `RWX/Block`). Receiver
binds RWX/Block 30Gi = 32212254720 bytes (byte-identical to source), pipeline reaches
`Initialize/PrepareTarget/Synchronization = Completed`, target VMI `Running`. Verified end to end.

## Root cause
`qemu` opens the target as a `raw` blockdev sized to the source device (32212254720). On a Filesystem
PVC the containing file is smaller than that, so the copy target is too small → hard failure. Nothing
in the MTV plan validation compares the receiver's usable size / volume mode against the source raw
device before starting.

## Expected behavior (fix request)
- MTV should **pin the receiver `volumeMode` to match the source disk** (Block for a Block source)
  when generating the StorageMap, **or**
- size a Filesystem receiver with enough headroom for the source's raw device size, **and**
- add a pre-flight validation that fails the plan early (clear message) instead of surfacing an
  opaque `qemu` size / `Input/output error` after the source VM has already been disrupted.
- The ACM "Cross cluster migration" quick action generates the StorageMap with `volumeMode` unset and
  starts immediately, giving the user no chance to correct it — it should default to Block for
  virtualization storage.

## Notes / evidence
- Wizard-generated StorageMaps (real UI clicks) all map
  `ocs-storagecluster-ceph-rbd-virtualization → ocs-storagecluster-ceph-rbd-virtualization` with
  `destination.volumeMode` empty (one sets only `accessMode: ReadWriteMany`). Destination is correct;
  volume mode is simply not pinned.
- `StorageProfile` defaults in this cluster: `ceph-rbd-virtualization → {RWX, Block}` (so the
  unpinned map happens to yield Block and works); a Filesystem-defaulting profile would fail.
