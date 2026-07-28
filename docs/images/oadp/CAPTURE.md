# OADP scheduled-backup (use case 4) — screenshots

✅ **Captured on the live three-cluster environment (2026-07-18)** and wired into README use case 4:
`01-dpa-available.png` (BSL `dr-s3` Available), `02-vm-running.png` (`vm-dr-example` Running / Fedora),
`03-schedule-created.png` (the label-created Velero `Schedule`, `*/5`, 1h TTL), `04-backups-accumulating.png`
(6 backups landing 5 min apart via the data mover), `05-policy-compliant.png` (policy Compliant in ACM
Governance). Captured with a headless-Chromium (Playwright) console login. To re-capture after changes,
re-run that flow against the cluster2 console (VM/Schedule/Backups) and the hub console (Governance).

Original shot list (kept for reference / re-capture):

Prereqs for a live capture: `operators` (installs OADP on the spokes) → `oadp` (bucket + DPA + the
`oadp-vm-backup-schedule` policy) → a VM to protect (`virt`) → label the VM.

## Shots — `docs/images/oadp/`

| File | Where / how to capture | Should clearly show |
|------|------------------------|---------------------|
| `01-dpa-available.png` | OpenShift console (spoke) → **Operators → Installed Operators → OADP → DataProtectionApplication `dpa-dr`**, or `oc get dpa,backupstoragelocation -n openshift-adp` | The DPA reconciled and the `dr-s3` `BackupStorageLocation` **Available** (bucket reachable). |
| `02-vm-labelled.png` | Console → **Virtualization → VirtualMachines → vm-dr-example → labels**, or `oc get vm vm-dr-example -n vm-example --show-labels` | The `oadp-backup=true` label on the VM — the trigger for the policy. |
| `03-schedule-created.png` | `oc get schedule -n openshift-adp -o wide`, or console YAML of the Velero `Schedule` | `vm-dr-example-scheduled-backup` **Enabled**, `schedule: */5 * * * *`, `ttl: 1h0m0s` — created by the ACM policy from the label. |
| `04-backups-accumulating.png` | `oc get backup -n openshift-adp -l velero.io/schedule-name=vm-dr-example-scheduled-backup --sort-by=.metadata.creationTimestamp` (wait ~15+ min) | Several `Completed` backups spaced 5 min apart, with the oldest expiring near the 1h TTL — i.e. the "confirm the number of backups" evidence (~12 at steady state). |
| `05-policy-compliant.png` | ACM console → **Governance → Policies → oadp-vm-backup-schedule** | The policy **Compliant** on the spokes (schedules created; the confirm-policy green once the first backup lands). |
| `06-backup-in-bucket.png` _(optional)_ | AWS S3 console (or `aws s3 ls s3://oadp-dr-<acct>/velero/backups/`) | Backup objects landing in the shared S3 bucket. |

## After capturing

1. Drop the PNGs into this directory with the exact filenames above.
2. Uncomment the matching `<!-- ![…](docs/images/oadp/…) -->` slots in `README.md` (use case 4, step 4).
3. Remove the "screenshots pending a live run" note.
