# ForgeVM on AWS — automated sandbox deployment

Terraform + a bash bootstrap that provisions a single EC2 host with **nested
virtualization** enabled and runs [ForgeVM](https://github.com/DohaerisAI/forgevm)
— a self-hosted, MIT-licensed code-execution sandbox — using its **Firecracker
microVM provider** for true hardware isolation (~28–35 ms snapshot restore).

The instance family and the `NestedVirtualization=enabled` CPU option are what
let a non-metal EC2 instance expose `/dev/kvm`, which Firecracker requires.

---

## What gets created

| Resource | Detail |
|---|---|
| EC2 instance | `m7i-flex.large` (2 vCPU / 8 GiB), Amazon Linux 2023 x86_64, **nested virtualization enabled** |
| Root EBS | 40 GiB gp3, encrypted |
| Elastic IP | stable public address (survives the stop/start used by the CLI path) |
| Security group | inbound `22` (SSH) + `7423` (ForgeVM API), scoped to a single CIDR |
| Key pair | created from your local public key |
| Bootstrap | KVM check → Docker + xfsprogs → XFS reflink volume → ForgeVM install → `forgevm.service` |

**Estimated cost:** ~$72–90/month if left running (instance ~$70, EBS ~$2.40,
public IPv4 ~$3.60). `terraform destroy` stops all of it. See
[Managing cost](#managing-cost).

---

## Prerequisites

- **Terraform** ≥ 1.6.
- **AWS credentials** via environment variables (this setup uses the default
  credential chain — no named profile):
  ```bash
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  # export AWS_SESSION_TOKEN=...   # if using temporary credentials
  ```
- **An SSH key** — either let Terraform generate one (`generate_ssh_key = true`,
  written to `generated_key_path`, default `./forgevm-ssh-key.pem`), or supply
  an existing public key via `public_key_path` (default `~/.ssh/id_rsa.pub`;
  create one with `ssh-keygen -t ed25519` if you don't have it).
- **A subnet** — by default the instance goes into your **default VPC**. If your
  account has no default VPC (common on corporate accounts, and it shows up as
  `Error: no matching EC2 VPC found`), set `subnet_id` to a **public** subnet.
  List candidates with:
  ```bash
  aws ec2 describe-subnets \
    --query 'Subnets[].{ID:SubnetId,VPC:VpcId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' \
    --output table
  ```
- **AWS CLI ≥ 2.33.21** — required **only** if you use
  `nested_virtualization_method = "cli"` (see below). Not needed for the default
  `"provider"` path.

The IAM identity behind those credentials needs permission to manage EC2
(instances, security groups, key pairs, EIPs), read the AL2023 SSM public
parameter, and — for the CLI path — `ec2:StopInstances`, `ec2:StartInstances`,
and `ec2:ModifyInstanceCpuOptions`.

### Creating a scoped IAM user

A ready-to-use least-privilege policy is provided at
[`iam/forgevm-terraform-policy.json`](iam/forgevm-terraform-policy.json). It
grants only what this project needs and **locks all mutating EC2 actions to
`us-east-1`** via an `aws:RequestedRegion` condition (change that region in the
JSON if you deploy elsewhere).

From the AWS console (sign in as an admin, not for day-to-day use):

1. **IAM → Policies → Create policy → JSON**, paste the file's contents, and
   name it `forgevm-terraform`.
2. **IAM → Users → Create user** (e.g. `forgevm-deployer`); do **not** grant
   console access — this is a programmatic-only user. Attach the
   `forgevm-terraform` policy directly.
3. **User → Security credentials → Create access key → CLI**. Copy the
   **secret access key** — it's shown only once.
4. Put the credentials in your environment (see above) and confirm with
   `aws sts get-caller-identity`.

If an `apply` ever fails with `UnauthorizedOperation` naming an `ec2:` action
not in the policy, add just that action to the `ManageEC2InUsEast1` statement.
Rotate or delete the access key when you're done — long-lived keys are the main
risk with IAM users.

---

## Nested virtualization — the key constraint

As of Feb 2026 AWS exposes `/dev/kvm` on **non-metal** instances, but only on
specific families: **c8i, m8i, r8i, c8id, r8id, m8id, c8i-flex, r8i-flex,
m8i-flex, X8i, C7i, R7i, M7i, C7i-flex, M7i-flex, I7i**. It must be turned on
explicitly — it is **not** on by default and **not** exposed in the AWS console.
The `instance_type` variable is validated against this family list.

This project offers two ways to enable it, via `nested_virtualization_method`:

- **`"provider"` (default)** — sets `cpu_options { nested_virtualization =
  "enabled" }` on `aws_instance` at launch. Cleanest, single `apply`, no stop/
  start. Needs a recent AWS provider that exposes the argument (run
  `terraform init -upgrade` to get the latest).
- **`"cli"` (fallback)** — launches the instance, then a `local-exec` runs
  `aws ec2 modify-instance-cpu-options --nested-virtualization enabled` on the
  stopped instance and restarts it. Works with any provider version but requires
  the AWS CLI locally. On this path `/dev/kvm` is absent during the *first*
  boot's bootstrap (advisory warning only); it appears after the restart and the
  `forgevm.service` picks it up automatically on the next boot.

> **Region note:** nested virtualization is documented for all commercial
> regions, but confirm the chosen family has capacity in your region/AZ before
> relying on it. Default region here is **us-east-1**.

---

## Quick start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional; defaults are sensible
terraform init          # add -upgrade to pull the latest AWS provider
terraform apply
```

Then wait ~3–5 minutes for first-boot bootstrap and check the outputs:

```bash
terraform output ssh_command          # ssh ec2-user@<ip>
terraform output forgevm_url          # http://<ip>:7423
terraform output bootstrap_log_hint   # tail the bootstrap log

# Health check once bootstrap finishes:
curl "$(terraform output -raw forgevm_url)/api/v1/sandboxes"
```

To run the on-host verifier:

```bash
ssh ec2-user@<ip> 'bash -s' < ../scripts/verify-kvm.sh
```

If `terraform plan` errors with **`Unsupported argument nested_virtualization`**,
your AWS provider is too old — run `terraform init -upgrade`, or set
`nested_virtualization_method = "cli"`.

---

## Using ForgeVM

ForgeVM listens on port **7423** and ships Python & TypeScript SDKs. The
security group only admits your IP, so point SDKs/`curl` at the Elastic IP:

```bash
BASE="http://<public_ip>:7423"
curl "$BASE/api/v1/sandboxes"
```

The systemd unit sets `FORGEVM_PROVIDERS_DEFAULT=firecracker` so sandboxes use
Firecracker microVMs (given `/dev/kvm` is present).

### Running code with third-party libraries

Sandboxes default to **no network**, so bake dependencies into a custom image
rather than `pip install` at runtime. See [`examples/`](examples/) for a
copy-paste workflow: a `Dockerfile` + `requirements.txt`, a host-side `build.sh`
(`docker build` + `forgevm build-image`), and `run.py` / `run.sh` that spawn a
sandbox, upload your code, execute it, and clean up.

---

## Day-to-day operations

Run everything from the `terraform/` directory. Commands that reference the
instance pull its ID/IP straight from the Terraform outputs, so they keep
working across rebuilds.

### Lifecycle (mind the ~$70/mo meter — don't leave it running idle)

```bash
# Pause compute charges — keeps the disk, install, and (via the Elastic IP) the
# same public address. forgevm.service and the XFS mount are persistent, so it
# comes back ready on start:
aws ec2 stop-instances  --instance-ids "$(terraform output -raw instance_id)"
aws ec2 wait instance-stopped --instance-ids "$(terraform output -raw instance_id)"

# Resume later:
aws ec2 start-instances --instance-ids "$(terraform output -raw instance_id)"
aws ec2 wait instance-running --instance-ids "$(terraform output -raw instance_id)"

# Tear everything down → billing goes to $0 (rebuild later with `terraform apply`):
terraform destroy
```

Stopped, you still pay a little for the EBS volume + idle Elastic IP (~$6/mo).
`terraform destroy` is the only thing that stops all charges.

### Inspect / connect

```bash
terraform output                      # all outputs (IP, URLs, commands)
eval "$(terraform output -raw ssh_command)"          # SSH in
eval "$(terraform output -raw bootstrap_log_hint)"   # tail first-boot log
```

### Drive ForgeVM

```bash
BASE="$(terraform output -raw forgevm_url)"          # http://<ip>:7423

curl -sS "$BASE/api/v1/sandboxes"                    # list sandboxes

# Pre-build a rootfs image (first build is slower; then it's cached):
eval "$(terraform output -raw ssh_command)" 'sudo forgevm build-image alpine:latest'

# Create a sandbox (returns an id like sb-XXXXXXXX):
curl -sS -X POST "$BASE/api/v1/sandboxes" \
  -H 'Content-Type: application/json' -d '{"image":"alpine:latest"}'
```

### On-instance service management

```bash
sudo systemctl status forgevm          # is it running?
sudo systemctl restart forgevm         # after config changes
sudo journalctl -u forgevm -n 50       # recent logs
```

### Quick reference

| Goal | Command |
|---|---|
| Preview infra changes | `terraform plan` |
| Create / update infra | `terraform apply` |
| Show outputs | `terraform output` |
| Pause billing | `aws ec2 stop-instances --instance-ids "$(terraform output -raw instance_id)"` |
| Resume | `aws ec2 start-instances --instance-ids "$(terraform output -raw instance_id)"` |
| Destroy (bill → $0) | `terraform destroy` |
| SSH in | `eval "$(terraform output -raw ssh_command)"` |
| Health check | `curl "$(terraform output -raw forgevm_url)/api/v1/sandboxes"` |

---

## Troubleshooting

- **`/dev/kvm` missing / no `vmx`/`svm`** — nested virtualization didn't take.
  Confirm `instance_type` is in the supported family list, and that the CPU
  option is actually set: `aws ec2 describe-instances --instance-ids <id>
  --query 'Reservations[].Instances[].CpuOptions'`. On the `"cli"` path, make
  sure the `local-exec` stop/modify/start completed (re-run `terraform apply`).
- **`Unsupported argument nested_virtualization`** — old AWS provider; see
  [Quick start](#quick-start).
- **API not reachable remotely** (localhost works, your IP doesn't) — the
  bootstrap sets `FORGEVM_HOST=0.0.0.0`, but if this ForgeVM build ignores that
  and only binds localhost, adjust the bind address per ForgeVM's docs in
  `/etc/systemd/system/forgevm.service`, then `sudo systemctl daemon-reload &&
  sudo systemctl restart forgevm`. Also confirm `allowed_cidr` still matches
  your current public IP.
- **Sandbox create fails: `mount … failed: Invalid argument`** — ForgeVM builds
  ext4 rootfs images and loop-mounts them, but AL2023 runs on XFS so the `ext4`
  kernel module isn't loaded by default. **The bootstrap now loads it** (`modprobe
  ext4` + `/etc/modules-load.d/forgevm.conf`). If you ever see this, run
  `sudo modprobe ext4` and retry.
- **Docker didn't install / `build-image` says `docker … not found in PATH`** —
  the classic cause on AL2023 is a `dnf` package conflict: requesting the full
  `curl` package clashes with the preinstalled `curl-minimal` and fails the
  whole install transaction. **The bootstrap avoids this** (it no longer
  requests `curl`) and uses a soft `Wants=docker.service` so ForgeVM starts
  regardless. To fix an affected box by hand:
  `sudo dnf -y install docker && sudo systemctl enable --now docker && sudo systemctl restart forgevm`.
- **Bootstrap details** — `sudo tail -f /var/log/forgevm-bootstrap.log` and
  `systemctl status forgevm` on the instance.

> **Note:** all four issues hit during initial bring-up (no default VPC, missing
> SSH key, Docker install, ext4 module) are handled by the current Terraform and
> bootstrap — a fresh `terraform destroy && terraform apply` comes up working
> without manual intervention.

---

## File layout

```
terraform/
  versions.tf              provider + version constraints
  providers.tf             AWS provider (env-var credentials, default tags)
  variables.tf             all inputs (region, instance_type, method, ...)
  main.tf                  AMI/VPC lookups, key, SG, instance, EIP, CLI fallback
  outputs.tf               IP, SSH command, API URL, health-check hints
  user_data.sh.tftpl       first-boot bootstrap (KVM/Docker/XFS/ForgeVM/systemd)
  terraform.tfvars.example copy to terraform.tfvars
scripts/
  verify-kvm.sh            on-host health check
iam/
  forgevm-terraform-policy.json   least-privilege IAM policy for the deploy user
examples/
  Dockerfile, requirements.txt, app/, build.sh, run.py, run.sh
                           running Python-with-dependencies in a sandbox
```

## Security notes

- SSH (22) and the ForgeVM API (7423) are restricted to `allowed_cidr` (your
  IP by default). The API has no auth in front of it here — do not widen the
  CIDR to `0.0.0.0/0`.
- Root EBS is encrypted; IMDSv2 is enforced.
- `terraform.tfvars`, state files, and `*.pem` are gitignored.
