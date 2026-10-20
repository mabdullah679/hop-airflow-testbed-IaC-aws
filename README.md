# hop-airflow-testbed-IaC-aws

A small, real data-pipeline testbed: Apache Airflow orchestrates an Apache Hop pipeline (`hop-run`) over a sample orders dataset in S3, and the whole thing is provisioned with Terraform and deployed through GitHub Actions (OIDC, no stored AWS keys).

Spec: the task brief for this session (Airflow + Hop testbed as IaC on AWS). **Authorship note:** this repository was empty and was authored from scratch in a single Claude Code session on 2026-10-20; no prior code existed.

## Runtime / deploy flow

```
 git push (prod-hardening)
        |
        v
 GitHub Actions --OIDC--> IAM role pf-hop-airflow-gha-deploy
   test -> terraform fmt/validate -> plan -> apply -> deploy.sh via SSM -> smoke test
        |
        v                         AWS ap-southeast-2 (own VPC, no NAT)
 +---------------------------------------------------------------+
 |  EC2 t3.medium (Docker)                    S3 data bucket     |
 |   Airflow web+scheduler (LocalExecutor) -> input/orders.csv   |
 |   Postgres (metadata)                      output/<run>/...   |
 |   DAG: fetch_and_validate -> run_hop_pipeline -> verify_and_publish
 |                               (hop-run, Java 21)              |
 +---------------------------------------------------------------+
   :8080 open ONLY to the owner's /32; admin password in SSM
```

Not local/contained: an AWS account (346208529954 in this run) and a GitHub repo with OIDC trust; the sample data and Hop run on the instance, S3 and SSM are AWS services.

## Prerequisites

- AWS account with the shared GitHub OIDC provider and the `portfolio-ci-boundary` policy already present; region `ap-southeast-2`.
- Terraform >= 1.10 locally (needed for `use_lockfile`; the CI pins 1.12.2).
- Docker (only for running the tests locally), Python 3.11+ with `pytest`.
- Host needs NO Java, Hop or Airflow: they live in the image built from `app/Dockerfile`.
- An EC2 standard-vCPU quota of at least 2 free vCPUs (see Deployed on AWS).

## Run it

1. Bootstrap once (local apply; CI cannot create its own role or state bucket):
   `cd infra/bootstrap && terraform init && terraform apply`
2. Set the repo variable with your public IP: `gh variable set ALLOWED_CIDR --body "$(curl -s https://checkip.amazonaws.com)/32"`
3. Push to `prod-hardening`. The `ci-deploy` workflow tests, plans, applies, runs `deploy.sh` on the instance and smoke-tests.
4. Get the URL: `terraform -chdir=infra output airflow_url`. Admin user is `admin`; the password is the SecureString SSM parameter `/pf-hop-airflow/airflow-admin-password` (generated on the instance at first deploy, never in git or logs).

If your IP changes, update `ALLOWED_CIDR` and push again; port 8080 is unreachable from anywhere else (`allowed_cidr` rejects `0.0.0.0/0`, see `infra/variables.tf`).

Tear down: `ALLOWED_CIDR=<your>/32 scripts/destroy.sh [--with-bootstrap]` (needs Terraform >= 1.10 and AWS credentials). It also deletes the two instance-created SSM secrets.

## What it does

| Action | Expected result |
|---|---|
| Open the Airflow URL without logging in | 302 redirect to login |
| Log in as `admin` | Home page (200); DAG `orders_hop_pipeline` visible |
| Trigger the DAG with defaults | `fetch_and_validate` -> `run_hop_pipeline` -> `verify_and_publish` all succeed; `output/<run_id>/orders_enriched.csv` and `output/latest/...` written to S3 |
| Output content | Rows with `unit_price <= 0` dropped, `line_total = unit_price * quantity` added (20 in, 18 out for the sample) |
| Trigger with `{"input_key":"input/orders_bad.csv"}` | `fetch_and_validate` fails with `InputValidationError`; downstream tasks `upstream_failed`; nothing published |

## Interfaces

| Interface | Method / path | Auth |
|---|---|---|
| Airflow UI | `GET :8080/` | admin login, SG-restricted to owner /32 |
| Airflow REST | `/api/v1/...` | session cookie (basic auth backend not enabled) |
| Health | `GET :8080/health` | none (same SG restriction) |
| DAG conf | `input_key` (default `input/orders.csv`) | n/a |
| Ops access | SSM Session Manager / Run Command | IAM (no SSH, port 22 closed) |

## Tests

- `pytest tests/test_checks.py` - pure validation logic; no AWS or Docker needed.
- `scripts/dag_import_test.sh [image]` - imports the DAG with real Airflow inside the app image and asserts task order.
- `scripts/hop_local_test.sh [image]` - runs the real `hop-run` on `app/data/orders.csv` and asserts 18 rows, `1001.line_total = 50.00`, no padded strings.
- CI runs all three plus `ruff`, `terraform fmt -check` and `terraform validate`; the deploy job ends with `scripts/smoke.sh` (triggers the DAG on the instance over SSM, expects SUCCESS and 18 rows in S3).
- No test needs live AWS except the smoke test.

Mutation checks done this session (guard broken, test watched go red, exact edit reversed): output-row-count guard, header guard (this found the first header test was too weak, so it was rewritten), DAG task order, and the Hop filter threshold (`> 0` changed to `> -100` produced 20 rows and failed the hop test). The padding assertion was added, seen red against the unpadded-length bug, then fixed.

## Layout

| Path | Role |
|---|---|
| [`app/Dockerfile`](app/Dockerfile) | Airflow 2.10.5 + Temurin 21 (checksum-verified) + Hop 2.19.0 (sha512-verified) |
| [`app/install_java.py`](app/install_java.py) | Fetches and verifies the JRE at build time |
| [`app/docker-compose.yml`](app/docker-compose.yml) | Postgres, init, webserver, scheduler |
| [`app/dags/orders_pipeline.py`](app/dags/orders_pipeline.py) | The DAG |
| [`app/dags/orders_checks.py`](app/dags/orders_checks.py) | Input validation + output assertion (unit-tested) |
| [`app/hop/orders_transform.hpl`](app/hop/orders_transform.hpl) | The Hop pipeline; `hop/config/` holds the `local` run configuration |
| [`app/data/orders.csv`](app/data/orders.csv) | 20-row sample input |
| [`app/deploy.sh`](app/deploy.sh) | Idempotent on-instance deploy; creates secrets in SSM |
| [`infra/`](infra/) | Terraform: VPC, SG, EC2, EIP, S3, IAM |
| [`infra/bootstrap/`](infra/bootstrap/) | State bucket + GitHub OIDC deploy role (applied locally once) |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | CI/CD |
| [`scripts/`](scripts/) | smoke, ssm_run, destroy, local test runners |
| [`tests/`](tests/) | pytest suites |

## Design decisions

- **Not MWAA.** About US$0.50/hr minimum; a single EC2 with Docker is roughly an eighth of that and enough for a testbed.
- **Hop reads a staged local file, not `s3://` directly.** The DAG downloads the object with boto3, validates it, and uploads the result. Alternative: Hop's S3 VFS. Not used because it was not tried and proven; this way every step is observable and the validation gate runs before Hop. Consequence: this is not a demonstration of Hop's native S3 VFS.
- **Secrets generated on the instance**, stored in SSM SecureString, so they never enter Terraform state or CI logs. Alternative `random_password` would put them in state.
- **UI over plain HTTP, restricted by SG to one /32.** Alternative ALB+ACM+auth costs more and needs a domain. Passwords cross the network unencrypted between you and the instance; use an SSM port-forward (`aws ssm start-session ... AWS-StartPortForwardingSession`) if that matters.
- **Smoke test via SSM**, because the CI runner's IP is (rightly) blocked by the SG.
- **Output asserted twice**: in the DAG (`assert_output_matches`) and independently in CI against the real Hop binary.
- **App bundle shipped through S3**, rebuilt on the box by `deploy.sh`, so no registry (ECR) cost.

## Deployed on AWS

Observed on 2026-10-20, account 346208529954, region ap-southeast-2:

- GitHub Actions run 39404934018 (branch `prod-hardening`, OIDC): test, terraform and deploy jobs all succeeded, ending with `SMOKE OK` (DAG run success, 18 output rows).
- Authenticated session against the live UI: unauthenticated `/home` returned 302, login returned 302 then `/home` 200; DAG `orders_hop_pipeline` listed (tags `hop`, `testbed`, not paused).
- Manual UI-API run `ui_good_1`: success; input `input/orders.csv` 20 rows; S3 object `output/ui_good_1/orders_enriched.csv` with 18 rows.
- Bad input run `ui_bad_1` (`input/orders_bad.csv`, non-numeric price): `fetch_and_validate` failed, other tasks `upstream_failed`. Fix run `ui_fixed_1` with the default input: success, 18 rows.
- Instance memory with the stack idle after runs: about 1.5 GiB used of 3.8 GiB (webserver ~780 MiB, scheduler ~390 MiB).

Resources (all named `pf-hop-airflow-*`, tagged `project=portfolio`, `repo=hop-airflow-testbed-IaC-aws`, `managed-by=terraform`): VPC, subnet, IGW, route table, security group, EC2 t3.medium, EIP, S3 data bucket (+ 9 objects), IAM role/policy/instance profile for the instance, IAM deploy role, S3 state bucket, 2 SSM parameters.

Honest limits: the first deploy attempt failed twice for real reasons (EC2 vCPU quota exhausted by other workloads in the shared account; then `install_java.py` missing from the S3 bundle). Both were fixed and the green run above is the one that counts. `terraform apply` was run locally only for the bootstrap step. Hourly cost is an estimate from published rates (not an invoice): ~US$0.062/hr (t3.medium ~0.0528, 30 GB gp3 ~0.004, public IPv4 ~0.005), about US$1.5/day.

Teardown and rebuild: the stack is meant to be destroyed after verification to save cost (`scripts/destroy.sh`, see above). To rebuild everything, re-run the Run-it steps (bootstrap only if the state bucket was also destroyed; otherwise push or re-run the workflow). At the time this README was written the stack was still running pending the owner's destroy instruction.

Not established: Hop's native S3 VFS; behaviour on instance types other than t3.medium; multi-user Airflow auth; long-running stability (observed for well under a day).
