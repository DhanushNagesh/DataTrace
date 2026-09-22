import os

import psycopg


def connect(**kwargs) -> psycopg.Connection:
    """Connects to the warehouse.

    Local and CLI use set DATABASE_URL. In Lambda there is no password: boto3 signs a 15-minute
    IAM token locally, with no API call, which is why a VPC Lambda needs no Secrets Manager
    endpoint and no NAT. RDS requires TLS for IAM auth.
    """
    url = os.environ.get("DATABASE_URL")
    if url:
        return psycopg.connect(url, **kwargs)

    import boto3

    host = os.environ["DB_HOST"]
    port = int(os.environ.get("DB_PORT", "5432"))
    user = os.environ["DB_USER"]
    token = boto3.client("rds").generate_db_auth_token(host, port, user)
    return psycopg.connect(
        host=host,
        port=port,
        user=user,
        dbname=os.environ.get("DB_NAME", "datatrace"),
        password=token,
        sslmode="require",
        **kwargs,
    )
