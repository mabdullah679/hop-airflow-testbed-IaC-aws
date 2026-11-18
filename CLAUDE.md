# CLAUDE.md (hop-airflow-testbed-IaC-aws)

Global working rules: `~/.claude/CLAUDE.md` (read it; not copied here). Repo-specific only below.

## Commands (run 2026-11-18)

```
pip install pytest ruff
ruff check app tests                      # clean
pytest -q tests/test_checks.py            # 7 passed (tests/ as a whole: 7 passed, 1 skipped; the skip is the DAG import test, needs Airflow)
docker build -t pf-hop-airflow:ci app     # Airflow 2.10.5 + Java 21 + Hop 2.19.0, downloads from the internet
bash scripts/dag_import_test.sh pf-hop-airflow:ci
bash scripts/hop_local_test.sh pf-hop-airflow:ci   # real hop-run, expects 18 rows
```
Terraform is not installed on the owner machine; `fmt`/`validate` run in CI only.

## Layout
`app/` (Dockerfile, DAGs, Hop pipeline, deploy.sh, sample data), `infra/` + `infra/bootstrap/` (Terraform), `scripts/` (tests, smoke, destroy), `tests/`, one workflow `.github/workflows/deploy.yml`.

## Conventions
- Feature branch + PR; never push to `main`. Note: a push to `prod-hardening` runs the deploy job (it applies Terraform to AWS). Do not push there without the owner's say-so. PRs from other branches only run checks.
- Pin third-party actions to full commit SHAs with a version comment.
- Logic fixes need a test seen failing first (mutate, see red, reverse the exact edit).

## Do NOT
- Run `terraform apply`/`destroy`, `scripts/destroy.sh`, or any `aws` call without explicit owner consent. The stack was torn down 2026-10-20.
- Put `0.0.0.0/0` in `allowed_cidr` (the variable rejects it on purpose).
- Commit `.env`, tfstate, or generated passwords.
