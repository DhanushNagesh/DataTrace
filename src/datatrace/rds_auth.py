import os


def iam_token(host: str, port: int, user: str) -> str:
    """A 15-minute database password, signed locally from the caller's IAM credentials.

    Its own module so the dbt image, which ships psycopg2 rather than psycopg, can import it.
    """
    import boto3

    return boto3.client("rds").generate_db_auth_token(host, port, user)


def token_from_env() -> str:
    return iam_token(
        os.environ["DB_HOST"],
        int(os.environ.get("DB_PORT", "5432")),
        os.environ["DB_USER"],
    )
