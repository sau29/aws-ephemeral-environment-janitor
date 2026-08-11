# Run Book: AWS Ephemeral Environment Janitor

## Overview

This repository provides a simple AWS lab to:

- validate a Terraform deployment against an existing VPC and Subnet
- confirm the target subnet has enough available IP addresses
- deploy EC2 instances and a cleanup Lambda engine
- verify deployed resources with AWS commands
- run the same deployment from GitHub Actions

## Scope of work

This implementation covers:

- existing AWS VPC and Subnet validation
- Terraform deployment of EC2 and security resources
- reserved capacity tracking inside the existing subnet
- local subnet availability validation via Python
- deployment through GitHub Actions
- verification steps for deployed AWS resources

## Prerequisites

- Windows PowerShell or another terminal
- Python 3.11 installed
- Terraform installed and on PATH
- AWS CLI installed and configured with valid credentials
- An existing AWS VPC ID and Subnet ID
- An existing S3 bucket for Terraform remote state
- GitHub repository secrets configured for AWS credentials when using GitHub Actions

## Repository layout

- `terraform/`: Terraform code for AWS infrastructure
- `python/`: validation and cleanup Python scripts
- `.github/workflows/`: GitHub Actions pipelines
- `scripts/`: local shell utilities

## Local setup

1. Open PowerShell and change to the repository root:

```powershell
cd "g:\My Drive\AI\Blog-1"
```

2. Create and activate a virtual environment:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

3. Install dependencies:

```powershell
pip install --upgrade pip
pip install -r requirements.txt
```

## Local validation and deployment steps

### 1. Run unit tests

```powershell
python -m pytest -q
```

### 2. Initialize Terraform with S3 backend

```powershell
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate"
```

> The S3 bucket must already exist and is configured in `terraform/main.tf`.

### 3. Create a Terraform plan

```powershell
terraform plan `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-0123456789abcdef0" `
  -var="subnet_id=subnet-0123456789abcdef0" `
  -out=tfplan.binary
```

### 4. Export plan to JSON

```powershell
terraform show -json tfplan.binary > tfplan.json
```

### 5. Validate subnet IP availability

```powershell
cd ..
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-0123456789abcdef0
```

### 5a. Simulate failure with a lower available IP count

```powershell
cd ..
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-0123456789abcdef0 --override-available-ips=1
```

### 5b. Simulate failure by overriding required IPs

```powershell
cd ..
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-0123456789abcdef0 --override-required-ips=10
```

### 6. Apply Terraform

```powershell
cd terraform
terraform apply -auto-approve tfplan.binary
```

## Deployment from GitHub Actions

### GitHub secrets required

Add the following secrets to your GitHub repository:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Workflow inputs

The workflow defined in `.github/workflows/ephemeral-pipeline.yml` requires:

- `env_name` — environment name (for state key and tags)
- `vpc_id` — existing VPC ID
- `subnet_id` — existing Subnet ID

Optional simulation inputs:

- `override_required_ips` — optional simulation override for required private IP count
- `override_available_ips` — optional simulation override for available private IP count

### Run via GitHub UI

1. Go to the `Actions` tab in your GitHub repository.
2. Select `Ephemeral Environment Pipeline`.
3. Click `Run workflow`.
4. Enter values for `env_name`, `vpc_id`, and `subnet_id`.
5. Run the workflow.

### Run via GitHub CLI

```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-0123456789abcdef0 `
  --field subnet_id=subnet-0123456789abcdef0
```

## AWS verification commands

After deployment, use these commands to verify resources.

### Check the subnet

```powershell
aws ec2 describe-subnets `
  --subnet-ids subnet-0123456789abcdef0 `
  --query "Subnets[0].{Id:SubnetId,Cidr:CidrBlock,Available:AvailableIpAddressCount}" `
  --output table
```

### Check EC2 instances

```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Environment,Values=dev" "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].{Id:InstanceId,Subnet:SubnetId,State:State.Name,Type:InstanceType}" `
  --output table
```

### Check the security group

```powershell
aws ec2 describe-security-groups `
  --filters "Name=group-name,Values=ephemeral-janitor-private-sg" `
  --query "SecurityGroups[].{Id:GroupId,Vpc:VpcId,Desc:Description}" `
  --output table
```

### Check available volumes tagged for the environment

```powershell
aws ec2 describe-volumes `
  --filters "Name=tag:Environment,Values=dev" "Name=status,Values=available" `
  --query "Volumes[].{Id:VolumeId,Size:Size,State:State}" `
  --output table
```

## Troubleshooting

- `terraform init` fails: confirm AWS credentials and S3 bucket access.
- `terraform plan` fails: ensure `vpc_id` and `subnet_id` are valid and in the same AWS region.
- `validate_subnet_ips.py` fails: verify the subnet exists and AWS credentials are correct.
- `terraform apply` fails: inspect Terraform output for resource or permission errors.

## Notes

- This repository expects an existing VPC/subnet rather than creating new networking.
- The workflow validates subnet capacity before applying Terraform.
- If validation fails, Terraform apply is skipped and no new resources are created.
- This preflight failure handling prevents bad deployments and avoids consuming subnet capacity.
- Stale resources from prior deployments are not handled by this validator; that is the responsibility of the cleanup/janitor logic after resources already exist.
- The local validation and GitHub workflow use the same deployment logic.
