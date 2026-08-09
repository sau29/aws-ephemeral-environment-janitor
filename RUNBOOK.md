# Run Book: AWS Ephemeral Environment Janitor

## Overview

This repository implements an AWS lab for ephemeral environment cleanup. It includes:

- Terraform IaC to provision a private VPC, private subnet, EC2 instances, and a Lambda cleanup engine
- Python automation for pre-flight validation and post-failure recovery
- GitHub Actions workflow for manual pipeline execution
- Local shell automation for failure simulation

## Design Summary

### Purpose
The application is designed to simulate ephemeral environment lifecycle issues and automated cleanup of leaked AWS resources.

### Key components

- `terraform/`: manages AWS infrastructure including VPC, private subnet, CIDR reservation, security group, EC2 instances, and Lambda packaging
- `python/scripts/validate_subnet_ips.py`: validates a Terraform plan against available subnet IP capacity
- `python/scripts/janitor_engine.py`: local Lambda-style cleanup utility that deletes orphaned EBS volumes and dangling ENIs for the target environment
- `scripts/run_local_simulation.sh`: end-to-end simulation that generates a plan, validates IP availability, applies Terraform, destroys resources, and runs local cleanup
- `.github/workflows/ephemeral-pipeline.yml`: workflow_dispatch pipeline for validating and optionally applying Terraform in GitHub Actions

## Architecture

### Terraform resources

- Private VPC `10.0.0.0/24`
- Private subnet `10.0.0.0/28`
- `aws_ec2_subnet_cidr_reservation` reserving `10.0.0.0/29` to create a constrained available IP pool
- Security group allowing TCP port `8080` within the VPC
- 3 `aws_instance` resources using `t2.micro` and `delete_on_termination = false` on the root volume
- Lambda packaging via `archive_file` and deployment with `aws_lambda_function` on Python 3.11
- IAM role/policy with least privilege for EC2 cleanup and CloudWatch Logs

### Failure scenario

- The private subnet and CIDR reservation leave only 2 usable IP addresses
- Terraform plan may request more private IP-consuming resources than available
- Instances with `delete_on_termination = false` simulate orphaned EBS volumes after destroy
- Local janitor engine removes leaked volumes and dangling ENIs when the environment is cleaned up

## Implementation Details

### `python/scripts/validate_subnet_ips.py`

- Accepts:
  - Terraform plan JSON path
  - AWS Subnet ID
- Parses `resource_changes` from `tfplan.json`
- Counts planned `aws_instance` and `aws_network_interface` create actions
- Calls `ec2.describe_subnets()` to get `AvailableIpAddressCount`
- Fails with exit code `1` if available IPs are less than required
- Prints structured pass/fail messages

### `python/scripts/janitor_engine.py`

- Lambda handler expects `event.environment_name`
- Finds EBS volumes in `available` state tagged:
  - `Environment = event.environment_name`
  - `Ephemeral = true`
- Deletes matching volumes
- Finds ENIs attached to security groups tagged with the same `Environment`
- Force-detaches `in-use` ENIs and deletes them
- Returns a JSON result with totals and detail arrays
- Uses Python `logging` for structured log events

### `terraform/janitor_lambda.tf`

- Packages `python/scripts/janitor_engine.py` as `terraform/janitor_engine.zip`
- Creates Lambda role with `sts:AssumeRole`
- Applies IAM policy granting:
  - `ec2:DescribeVolumes`
  - `ec2:DeleteVolume`
  - `ec2:DescribeNetworkInterfaces`
  - `ec2:DetachNetworkInterface`
  - `ec2:DeleteNetworkInterface`
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
- Deploys Lambda using Python 3.11 runtime

### GitHub Actions workflow

- Manual trigger via `workflow_dispatch`
- Accepts `env_name` and `subnet_id` inputs
- Sets up Python 3.11 and Terraform
- Configures AWS credentials from GitHub Secrets
- Runs `terraform init` with dynamic state key
- Plans and converts plan output to JSON
- Runs `validate_subnet_ips.py`
- Applies Terraform only when validation succeeds

## Prerequisites

- Git repository cloned locally
- Python 3.11 installed
- Terraform installed
- AWS credentials configured locally or available as GitHub secrets
- VS Code workspace open at repository root

## Local setup

```bash
cd "g:/My Drive/AI/Blog-1"
python -m venv .venv
.venv/Scripts/pip install --upgrade pip
.venv/Scripts/pip install -r requirements.txt
```

## Testing and verification

### 1. Run unit tests

```powershell
.\.venv\Scripts\Activate.ps1
python -m pytest -q
```

### 2. Validate terraform plan and subnet capacity

```powershell
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate"
terraform plan -var="environment_name=dev" -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json
cd ..
.\.venv\Scripts\python.exe python/scripts/validate_subnet_ips.py terraform/tfplan.json subnet-0123456789abcdef0
```

### 3. Run the local failure-and-recovery simulation

```bash
cd "g:/My Drive/AI/Blog-1"
./scripts/run_local_simulation.sh subnet-0123456789abcdef0 dev
```

- This performs plan generation, validation, apply, destroy, orphan detection, and cleanup
- It expects the environment to create orphaned volumes and then verifies cleanup

### 4. Trigger GitHub Actions workflow

1. Open GitHub repository workflow page
2. Select `Ephemeral Environment Pipeline`
3. Set `env_name` and `subnet_id`
4. Run workflow

### 5. Validate Lambda packaging

```bash
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate"
terraform apply -var="environment_name=dev" -auto-approve
```

Then verify `terraform/janitor_engine.zip` exists and Lambda can be created.

## Expected behavior

- `validate_subnet_ips.py` should detect IP shortage in the constrained subnet
- Terraform plan may still generate resources, but apply should be blocked until validation succeeds
- Destroy should leave orphaned EBS volumes due to `delete_on_termination = false`
- `janitor_engine.py` should purge those orphaned volumes and clean dangling ENIs
- Workflow should only apply after validation passes

## Troubleshooting

- If `terraform init` fails, verify AWS credentials and backend bucket access
- If `validate_subnet_ips.py` fails with AWS errors, confirm `subnet_id` exists and credentials are valid
- If `run_local_simulation.sh` fails, inspect script output and ensure `.venv` is active
- If orphaned EBS volumes remain after cleanup, confirm tags are correct and the environment name matches

## Notes

- This repository is intentionally scoped for ephemeral environment failure simulation, not production deployment
- Terraform state is stored dynamically per environment via `workflow_dispatch` inputs
- The local cleanup uses the same logic as the Lambda handler but runs directly from your workspace
