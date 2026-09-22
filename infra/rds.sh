#!/usr/bin/env bash
# Private Postgres instance for the warehouse. Run infra/network.sh first. Safe to re-run.
# BILLED: db.t4g.micro + 20 GB gp3 is about $14/month from creation until the instance is deleted.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"

INSTANCE=datatrace
PASSWORD_PARAM=/datatrace/rds/master-password

SUBNETS=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=datatrace-private-a,datatrace-private-b \
  --query 'Subnets[].SubnetId' --output text)
RDS_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=datatrace-rds \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ -z "$SUBNETS" ] || [ "$RDS_SG" = None ]; then
  echo "network not found; run infra/network.sh first" >&2
  exit 1
fi

# The master password is only for bootstrapping roles and break-glass access; the API and
# pipeline log in with IAM tokens. Parameter Store standard tier is free, Secrets Manager is not.
if ! aws ssm get-parameter --name "$PASSWORD_PARAM" >/dev/null 2>&1; then
  aws ssm put-parameter --name "$PASSWORD_PARAM" --type SecureString \
    --value "$(openssl rand -base64 32 | tr -d '/+=')" >/dev/null
fi

if ! aws rds describe-db-subnet-groups --db-subnet-group-name datatrace >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  aws rds create-db-subnet-group --db-subnet-group-name datatrace \
    --db-subnet-group-description "DataTrace private subnets" --subnet-ids $SUBNETS >/dev/null
fi

if ! aws rds describe-db-instances --db-instance-identifier "$INSTANCE" >/dev/null 2>&1; then
  # Backups kept 1 day: raw JSON in S3 is the source of truth and the warehouse can be rebuilt
  # from it. Storage autoscaling stays off so the bill can't grow on its own.
  aws rds create-db-instance \
    --db-instance-identifier "$INSTANCE" \
    --engine postgres --engine-version 17.11 \
    --db-instance-class db.t4g.micro \
    --allocated-storage 20 --storage-type gp3 \
    --db-name datatrace \
    --master-username datatrace_admin \
    --master-user-password "$(aws ssm get-parameter --name "$PASSWORD_PARAM" --with-decryption \
      --query Parameter.Value --output text)" \
    --db-subnet-group-name datatrace \
    --vpc-security-group-ids "$RDS_SG" \
    --no-publicly-accessible \
    --no-multi-az \
    --storage-encrypted \
    --enable-iam-database-authentication \
    --backup-retention-period 1 \
    --no-enable-performance-insights \
    --deletion-protection \
    --copy-tags-to-snapshot \
    --tags Key=project,Value=datatrace >/dev/null
  echo "creating $INSTANCE, usually 5-10 minutes..."
fi

aws rds wait db-instance-available --db-instance-identifier "$INSTANCE"
aws rds describe-db-instances --db-instance-identifier "$INSTANCE" \
  --query 'DBInstances[0].[Endpoint.Address,DbiResourceId,PubliclyAccessible,IAMDatabaseAuthenticationEnabled]' \
  --output text
