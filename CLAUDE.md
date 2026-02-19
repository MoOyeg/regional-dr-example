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
- `inventory/group_vars/all.yml` — Global defaults (OpenShift 4.20, m5.2xlarge, 120GB)
- `inventory/host_vars/` — Per-cluster configs (aws_credential_set, region, VPC, AMI, etc.)
- `templates/install-config.yaml.j2` — SNO install-config (1 master, 0 workers, OVNKubernetes)
- `Containerfile` — UBI9-based image with Ansible, AWS CLI, oc, openshift-install

## Development Conventions
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

## Known Issues / Gotchas
- `secret.sh` contains plaintext AWS credentials and is NOT gitignored — rotate keys and add to .gitignore
- The `destroy` command supports `--yes`/`-y` flag which passes `-e force_destroy=true` to the playbook
- install-config.yaml.j2 is SNO-specific: `bootstrapInPlace` with `/dev/xvda`
