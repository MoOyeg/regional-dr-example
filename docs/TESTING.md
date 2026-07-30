# DR use case test framework

Answers three questions for every use case: **do the documented prerequisite
commands still work**, **does the DR claim actually hold** (inject data, fail
over, read it back), and **when did it last pass, against what**.

```bash
./ansible-runner.sh test                          # functional tests, all use cases
./ansible-runner.sh test -e test_use_cases=5      # one use case (or "3,5")
./ansible-runner.sh test -e test_run_prereqs=true # also re-run the setup commands (slow)
./ansible-runner.sh test -e test_stage=prereq     # prereq | functional | all
```

Current results: [TEST-STATUS.md](TEST-STATUS.md) · ledger: `test-results/history.jsonl`

## Lifecycle

```
preflight -> env facts -> [prereq commands] -> seed -> action -> verify -> record
                                                                    |
                                                          (on failure) diagnostics
```

**Nothing is cleaned up after a failure.** The environment is left exactly as it
broke, and the artefacts that matter are captured to
`test-results/usecase<N>/<run-id>-diagnostics/`.

## Design rules

Each rule below exists because something looked healthy while being broken.

| Rule | The defect that bought it |
|---|---|
| Verify at the **receiver**, never the sender | A VolSync `ReplicationSource` published `lastSyncTime` for 12 minutes while the `ReplicationDestination` had never completed a sync (rotated PSK) |
| Assert the **payload**, not a status field | `pg_stat_wal_receiver` reported `streaming` while the LSN was frozen and the promotion deadlocked |
| Preflight the environment; unreachable ≠ failure ≠ pass | `rhsi --destroy` exited 0 with `failed=0` against three expired clusters, because its tasks are `ignore_errors: true` |
| Parse the `PLAY RECAP`, don't trust the exit code | Same as above |
| Match phases **exactly**, never by substring | `WaitingForPluginOperationsPartiallyFailed` is a real in-flight phase |
| Accept known-good non-ideal states | VM backups are legitimately `PartiallyFailed` (KubeVirt freeze hook, no guest agent) |
| Require a sane starting topology | A test that begins with two primaries, or none, proves nothing about the switchover |

## Per-use-case coverage

| # | Prereqs run | Seed | Action | Verified at the receiver |
|---|---|---|---|---|
| 1 | `app`, `virt` | *(guest marker - pending)* | DRPC `Failover` | VM Running on peer, old site drained, `Protected` returns |
| 2 | `cclm` | *(boot id + heartbeat on the VM's data disk, written by `cclm-demo/` cloud-init - read-back pending)* | `cclm-migrate` | VMI on target, migration Succeeded, source released |
| 3 | `app`, `volsync-dr` | MySQL row | flip `app-role` | Row readable from the promoted snapshot; new destination snapshot required **before** failover |
| 4 | `oadp` | ConfigMap in the VM namespace | delete the VM | Marker restored from S3, VM Running on peer, role flipped |
| 5 | `rhsi` | SQL row | flip `pg-role` | Row survived, site genuinely read-write, **reverse** replication works, write path followed |

Use cases 1 and 2, plus use case 3's `--vm` variant, need an in-guest marker
(cloud-init writes it, SSH reads it back) before their data claims can be
verified rather than inferred. Until then they assert orchestration only.

## Result record

`test-results/usecase<N>/<run-id>.json`, one line per run appended to
`test-results/history.jsonl`:

```json
{
  "use_case": {"id": "5", "name": "CNPG cross-site Postgres over RHSI"},
  "result": "pass",
  "caveats": {"git_dirty": false, "baseline_dirty": false},
  "git": {"commit": "e128962", "branch": "main", "dirty_files": 0},
  "environment": {"clusters": {"cluster2": "4.22.5"}, "operators": {"...": "..."}},
  "seed": {"marker": "uc5-...", "method": "sql-insert"},
  "verification": {"expected": "uc5-...", "actual": "uc5-...", "passed": true},
  "timings": {"switchover_s": 96}
}
```

`caveats.git_dirty` matters: a pass recorded from a modified working tree is not
reproducible, and [TEST-STATUS.md](TEST-STATUS.md) marks it.

## Observed baselines

Measured 2026-07-28 on the three-cluster environment; useful as SLO budgets:

| Use case | Measured |
|---|---|
| 1 Regional DR | 93 s to `FailedOver`, 198 s to VM Running, 8m11s to `Protected=True` |
| 2 CCLM | ~45 s, no reboot |
| 3 VolSync | ~50 s to VM on peer, 70 s to full convergence |
| 4 OADP | 74 s to role flip, 219 s to restored VM |
| 5 CNPG/RHSI | **50 s** switchover, unaided (2026-07-30); budget 300 s |

## Five use cases on one environment (2026-07-30)

All five were deployed side by side on a single three-cluster environment and
verified healthy simultaneously - no cleanup or teardown between them. They are
isolated by construction: separate namespaces, and three dedicated role labels
(`app-role`, `oadp-role`, `pg-role`) that never read each other. Use case 5 in
particular needs no `virt`, no `app` and no Submariner - only ODF storage and the
`dr-clusters` clusterset.

## RPO caveat for use case 3 (measured 2026-07-29)

VolSync rsyncs a **live, unquiesced** MySQL datadir, so the copy is
crash-inconsistent. A marker seeded ~60-90 s before the FIRST sync arrived as an
`.ibd` file whose dictionary state did not, and the failed-over database reported
`Table 'quarkusdb.dr_test' doesn't exist` - while replication itself was working
perfectly (the file was present on the standby volume). The same marker, given a
full settled sync cycle, recovered intact and the workload was serving on the
peer 62 s after the label flip.

So the honest boundary is: **writes are recoverable once a full sync cycle has
completed after them**; anything newer than the last completed sync may not be
readable even though the bytes replicated. The test now waits for two
destination snapshots after seeding, so it measures DR rather than that race.
