# dbt as a Lambda container image: dbt-postgres is far past the 250 MB zip limit.
# Built from the repo root: docker build -f infra/dbt.Dockerfile .
FROM public.ecr.aws/lambda/python:3.13

# Versions come from uv.lock, exported by infra/dbt.sh
COPY build/requirements-dbt.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements-dbt.txt

COPY dbt/ ${LAMBDA_TASK_ROOT}/dbt/
COPY src/datatrace/ ${LAMBDA_TASK_ROOT}/datatrace/

# Only /tmp is writable in Lambda, and dbt writes logs and compiled SQL on every run
ENV DBT_LOG_PATH=/tmp/dbt-logs DBT_TARGET_PATH=/tmp/dbt-target

CMD ["datatrace.dbt_handler.handler"]
