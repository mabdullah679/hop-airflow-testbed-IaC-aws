"""Airflow DAG: validate S3 input -> Apache Hop pipeline (hop-run) -> verify + publish to S3."""
import os
import shutil
from datetime import datetime

import boto3
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

from orders_checks import assert_output_matches, validate_orders_csv

BUCKET = os.environ.get("PIPELINE_BUCKET", "")
WORK = "/opt/airflow/work"
HPL = "/opt/airflow/hop/orders_transform.hpl"


def _s3():
    return boto3.client("s3", region_name=os.environ.get("AWS_REGION", "ap-southeast-2"))


def _fetch_and_validate(**ctx):
    key = ctx["dag_run"].conf.get("input_key", "input/orders.csv")
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(f"{WORK}/input")
    local = f"{WORK}/input/orders.csv"
    _s3().download_file(BUCKET, key, local)
    total, positive = validate_orders_csv(local)
    print(f"input s3://{BUCKET}/{key}: {total} rows, {positive} with positive price")
    ctx["ti"].xcom_push(key="expected_rows", value=positive)
    ctx["ti"].xcom_push(key="input_rows", value=total)


def _verify_and_publish(**ctx):
    expected = ctx["ti"].xcom_pull(task_ids="fetch_and_validate", key="expected_rows")
    out = f"{WORK}/output/orders_enriched.csv"
    actual = assert_output_matches(expected, out)
    dest = f"output/{ctx['run_id'].replace(':', '_')}/orders_enriched.csv"
    _s3().upload_file(out, BUCKET, dest)
    _s3().upload_file(out, BUCKET, "output/latest/orders_enriched.csv")
    print(f"published {actual} rows to s3://{BUCKET}/{dest}")


with DAG(
    dag_id="orders_hop_pipeline",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["hop", "testbed"],
) as dag:
    fetch = PythonOperator(task_id="fetch_and_validate", python_callable=_fetch_and_validate)
    hop = BashOperator(
        task_id="run_hop_pipeline",
        bash_command=(
            f"hop-run.sh --file={HPL} --runconfig=local "
            f"--parameters=INPUT_FILE={WORK}/input/orders.csv,OUTPUT_FILE={WORK}/output/orders_enriched"
        ),
    )
    publish = PythonOperator(task_id="verify_and_publish", python_callable=_verify_and_publish)
    fetch >> hop >> publish
