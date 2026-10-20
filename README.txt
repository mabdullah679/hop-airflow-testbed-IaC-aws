hop-airflow-testbed-IaC-aws  (plain-language version)

WHAT IT IS
A small working example of a data pipeline. A tool called Airflow runs a job on a schedule or on demand. That job downloads a small orders file from AWS storage (S3), checks it is valid, runs a transformation using Apache Hop, checks the result, and saves it back to S3. Everything in AWS is built by Terraform scripts and deployed automatically by GitHub Actions without any stored AWS passwords.

WHO WROTE IT
The repository was empty. All of it was written from scratch in one Claude Code session on 2026-10-20. Nothing pre-existed.

HOW IT RUNS
You push code to the branch prod-hardening. GitHub Actions runs the tests, builds the plan, applies it to AWS, updates the server, then runs a smoke test that triggers the job and checks the result. One small server (EC2 t3.medium) in its own private network runs Airflow, its database, and Hop in Docker. The Airflow web page is reachable only from the owner's own internet address. The admin password is generated on the server and kept in AWS Parameter Store; it is never in git or logs.

WHAT YOU CAN DO
Open the Airflow URL: without logging in you are sent to the login page. Log in as admin. You see the job orders_hop_pipeline. Run it: it takes the 20-row sample orders, drops the rows with a zero or negative price (2 rows), adds a line_total column (price times quantity), and writes 18 rows to S3. If you point it at a broken input file, the first step fails with a clear error and nothing is published.

HOW TO RUN IT
1. Create the state bucket and the GitHub login role once with Terraform in infra/bootstrap (done from a laptop, because the pipeline cannot create its own role). Needs Terraform 1.10 or newer.
2. Store your public IP as the GitHub variable ALLOWED_CIDR.
3. Push to prod-hardening and wait for the workflow.
4. Read the URL with terraform output airflow_url. Read the password from the SSM parameter /pf-hop-airflow/airflow-admin-password.
To remove everything: scripts/destroy.sh (add --with-bootstrap to also remove the state bucket).

TESTS
Unit tests for the checking code, a test that loads the job inside the real Airflow image, a test that runs the real Hop on the sample file and expects exactly 18 rows, plus code style and Terraform checks, plus the smoke test after deploy. To prove the tests are real, parts of the code were deliberately broken and the tests were seen to fail, then the code was restored. One test turned out to be too weak this way and was rewritten.

WHAT WAS PROVEN ON AWS (2026-10-20)
The workflow run 39404934018 passed all three jobs and the smoke test. Logging in to the live page worked. A manual run succeeded: 20 rows in, 18 rows out, file present in S3. A run with a bad input file failed visibly at the first step. A run with the good input afterwards succeeded again with 18 rows.

WHAT WENT WRONG ALONG THE WAY
The first deploy was refused because other projects in the shared account were using all the allowed server CPUs; it was retried once capacity freed up. The second attempt left the server without a build file because one file was missing from the upload list; that was fixed and redeployed. Also the first output file had extra blank padding after the region names; a new check caught it and it was fixed.

COST AND STATE
It was checked live on 2026-10-20 (deployed by GitHub Actions, good run, bad-input run and fixed run all behaved as expected, 20 rows in and 18 rows out) and then taken down the same day to save money. The cost while it ran was about 6 US cents per hour, from published prices and not from a bill. After removal, direct checks found no servers, addresses, disks, network parts, buckets, roles or secrets left over. The shared GitHub login provider and the shared permission boundary were not touched.

HOW TO BUILD IT AGAIN
1. In infra/bootstrap run terraform init and terraform apply (recreates the state bucket and the GitHub login role; needs Terraform 1.10 or newer).
2. Save your public IP as the GitHub variable ALLOWED_CIDR.
3. Run: gh workflow run ci-deploy.yml --ref prod-hardening (after the pull request is merged into main). Always use the prod-hardening branch because the AWS role only trusts that branch. Until the merge, push any commit to prod-hardening instead.
4. When the workflow is green, read the URL with terraform output airflow_url.

NOT PROVEN
Hop reading directly from S3 (the job downloads the file first, on purpose). Other server sizes. Long-term stability beyond a few hours. The page uses plain HTTP, limited to one IP address.
