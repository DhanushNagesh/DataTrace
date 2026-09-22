#!/usr/bin/env bash
# Private network for RDS and the in-VPC Lambdas. Safe to re-run. Nothing here is billed.
#
# The VPC has no internet gateway, so nothing in it can be reached from, or reach, the internet.
# RDS can't be made public by a stray setting, and the Lambdas need no NAT.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"

tags() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=project,Value=datatrace}]"; }

# authorize/revoke fail when the rule is already there / already gone; both mean done
idempotent() {
  local out
  if ! out=$("$@" 2>&1); then
    grep -qE 'InvalidPermission\.(Duplicate|NotFound)' <<<"$out" || { echo "$out" >&2; return 1; }
  fi
}

VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=datatrace \
  --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" = None ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 \
    --tag-specifications "$(tags vpc datatrace)" --query Vpc.VpcId --output text)
  aws ec2 wait vpc-available --vpc-ids "$VPC_ID"
fi

# RDS needs subnets in at least two AZs even for a single-AZ instance
subnet() {
  local id
  id=$(aws ec2 describe-subnets --filters Name=tag:Name,Values="$1" \
    --query 'Subnets[0].SubnetId' --output text)
  if [ "$id" = None ]; then
    id=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --availability-zone "$2" --cidr-block "$3" \
      --tag-specifications "$(tags subnet "$1")" --query Subnet.SubnetId --output text)
  fi
  echo "$id"
}
SUBNET_A=$(subnet datatrace-private-a us-east-2a 10.20.1.0/24)
SUBNET_B=$(subnet datatrace-private-b us-east-2b 10.20.2.0/24)

# The main route table only has the VPC-local route. Named so the S3 gateway endpoint can find it.
RTB_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$VPC_ID" Name=association.main,Values=true \
  --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-tags --resources "$RTB_ID" --tags Key=Name,Value=datatrace-private Key=project,Value=datatrace

sg() {
  local id
  id=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' --output text)
  if [ "$id" = None ]; then
    id=$(aws ec2 create-security-group --vpc-id "$VPC_ID" --group-name "$1" --description "$2" \
      --tag-specifications "$(tags security-group "$1")" --query GroupId --output text)
  fi
  echo "$id"
}
RDS_SG=$(sg datatrace-rds "Postgres, reachable only from DataTrace Lambda security groups")
API_SG=$(sg datatrace-api-lambda "API Lambda, may only open connections to Postgres")
PIPELINE_SG=$(sg datatrace-pipeline-lambda "Migration, loader and dbt Lambdas: Postgres and S3")

# Rules name the other security group, not an IP range: only ENIs carrying that group match.
# Security groups are stateful, so replies need no rule of their own.
to_group() { echo "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$1}]"; }
ALL_OUT='IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]'

idempotent aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" --ip-permissions "$(to_group "$API_SG")"
idempotent aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" --ip-permissions "$(to_group "$PIPELINE_SG")"
idempotent aws ec2 revoke-security-group-egress --group-id "$RDS_SG" --ip-permissions "$ALL_OUT"
idempotent aws ec2 revoke-security-group-egress --group-id "$API_SG" --ip-permissions "$ALL_OUT"
idempotent aws ec2 authorize-security-group-egress --group-id "$API_SG" --ip-permissions "$(to_group "$RDS_SG")"

# The pipeline group keeps its default outbound rule: it needs Postgres and S3 over 443.
# Gateway endpoint: S3 traffic gets a route inside the VPC, so the loader reaches S3 with no
# internet gateway and no NAT. Free, and only S3 and DynamoDB have this kind of endpoint.
S3_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values="com.amazonaws.${AWS_REGION}.s3" \
  --query 'VpcEndpoints[0].VpcEndpointId' --output text)
if [ "$S3_ENDPOINT" = None ]; then
  S3_ENDPOINT=$(aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --vpc-endpoint-type Gateway \
    --service-name "com.amazonaws.${AWS_REGION}.s3" --route-table-ids "$RTB_ID" \
    --tag-specifications "$(tags vpc-endpoint datatrace-s3)" \
    --query VpcEndpoint.VpcEndpointId --output text)
fi

echo "VPC_ID=$VPC_ID"
echo "SUBNET_IDS=$SUBNET_A,$SUBNET_B"
echo "ROUTE_TABLE_ID=$RTB_ID"
echo "RDS_SG=$RDS_SG"
echo "API_SG=$API_SG"
echo "PIPELINE_SG=$PIPELINE_SG"
echo "S3_ENDPOINT=$S3_ENDPOINT"
