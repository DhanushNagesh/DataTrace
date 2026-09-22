import os

import psycopg

from datatrace.rds_auth import iam_token


def connect(**kwargs) -> psycopg.Connection:
    """Connects to the warehouse.

    Local and CLI use set DATABASE_URL. In Lambda there is no password: boto3 signs a 15-minute
    IAM token locally, with no API call, which is why a VPC Lambda needs no Secrets Manager
    endpoint and no NAT. RDS requires TLS for IAM auth.
    """
    url = os.environ.get("DATABASE_URL")
    if url:
        return psycopg.connect(url, **kwargs)

    host = os.environ["DB_HOST"]
    port = int(os.environ.get("DB_PORT", "5432"))
    user = os.environ["DB_USER"]
    token = iam_token(host, port, user)
    return psycopg.connect(
        host=host,
        port=port,
        user=user,
        dbname=os.environ.get("DB_NAME", "datatrace"),
        password=token,
        sslmode="require",
        **kwargs,
    )
