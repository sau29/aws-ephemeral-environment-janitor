# AWS Ephemeral Environment Janitor

This repository contains an AWS lab that validates subnet IP capacity before deploying resources, and uses a cleanup engine for orphaned volumes and network interfaces.

## What is included

- `terraform/`: Terraform infrastructure code
- `python/`: Python validation and janitor scripts
- `.github/workflows/`: GitHub Actions deployment workflow
- `scripts/`: local execution helpers

## Scope of work

This implementation:

- assumes an existing AWS VPC and Subnet
- validates that the target subnet has enough free IP addresses before applying Terraform
- deploys EC2 instances and related networking/security infrastructure
- packages a cleanup Lambda engine for orphaned AWS resources
- supports deployment from local PowerShell and GitHub Actions

## Prerequisites

- Windows PowerShell or another shell
- Python 3.11 installed
- Terraform installed and on your PATH
- AWS CLI installed and configured with valid credentials
- An existing AWS VPC ID and Subnet ID
- An S3 bucket already created for Terraform remote state
- GitHub repository secrets configured for AWS credentials if using GitHub Actions

## Local setup

```powershell
cd "g:\My Drive\AI\Blog-1"
python -m venv .venv
.\.venv\Scripts\pip.exe install --upgrade pip
.\.venv\Scripts\pip.exe install -r requirements.txt
```

## Local verification

### 1. Run unit tests

```powershell
.\.venv\Scripts\Activate.ps1
python -m pytest -q
```

### 2. Initialize Terraform backend

```powershell
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate"
```

> The S3 backend bucket is already defined in `terraform/main.tf`.

### 3. Create a plan

```powershell
terraform plan `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-0123456789abcdef0" `
  -var="subnet_id=subnet-0123456789abcdef0" `
  -out=tfplan.binary
```

### 4. Convert plan to JSON

```powershell
terraform show -json tfplan.binary > tfplan.json
```

### 5. Validate subnet IP availability

```powershell
cd ..
.\.venv\Scripts\python.exe python/scripts/validate_subnet_ips.py terraform/tfplan.json subnet-0123456789abcdef0
```

### 6. Apply Terraform if validation passes

```powershell
cd terraform
terraform apply -auto-approve tfplan.binary
```

## GitHub Actions deployment

### Required GitHub secrets

In your repository settings, add:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Workflow inputs

The workflow is defined in `.github/workflows/ephemeral-pipeline.yml` and requires:

- `env_name` — environment name, e.g. `dev`
- `vpc_id` — existing AWS VPC ID
- `subnet_id` — existing AWS Subnet ID

### Trigger from GitHub UI

1. Open your GitHub repository.
2. Go to the `Actions` tab.
3. Select `Ephemeral Environment Pipeline`.
4. Click `Run workflow`.
5. Enter `env_name`, `vpc_id`, and `subnet_id`.
6. Start the workflow.

### Trigger from GitHub CLI

```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-0123456789abcdef0 `
  --field subnet_id=subnet-0123456789abcdef0
```

## AWS verification after deploy

### Check subnet details

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

### Check security group

```powershell
aws ec2 describe-security-groups `
  --filters "Name=group-name,Values=ephemeral-janitor-private-sg" `
  --query "SecurityGroups[].{Id:GroupId,Vpc:VpcId,Desc:Description}" `
  --output table
```

### Check orphaned volumes

```powershell
aws ec2 describe-volumes `
  --filters "Name=tag:Environment,Values=dev" "Name=status,Values=available" `
  --query "Volumes[].{Id:VolumeId,Size:Size,State:State}" `
  --output table
```

## Notes

- The code now uses an existing VPC and Subnet rather than creating new networking.
- The subnet validation step uses `validate_subnet_ips.py` and an AWS `describe_subnets` call.
- If the workflow fails due to validation, fix the subnet or use a larger Subnet CIDR before retrying.
