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
  - `pwsh` or `powershell` on Windows
  - `bash` / `zsh` on macOS/Linux
- Python 3.11 installed
  - `python --version`
- Terraform installed and on your PATH
  - `terraform version`
- AWS CLI installed and configured with valid credentials
  - `aws --version`
  - `aws configure`
- An existing AWS VPC ID and Subnet ID
  - `aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output table`
  - `aws ec2 describe-subnets --query 'Subnets[*].{Id:SubnetId,Vpc:VpcId,Cidr:CidrBlock,Available:AvailableIpAddressCount}' --output table`
  - Note: the GitHub workflow uses `test_fail_deployment=true` to simulate subnet IP exhaustion; leave it `false` for normal deployment.
- An S3 bucket already created for Terraform remote state
  - `aws s3api head-bucket --bucket your-bucket-name`
- GitHub repository secrets configured for AWS credentials if using GitHub Actions
  - `gh secret set AWS_ACCESS_KEY_ID`
  - `gh secret set AWS_SECRET_ACCESS_KEY`

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
  -out="tfplan"
```

### 4. Convert plan to JSON

```powershell
terraform show -json tfplan > tfplan.json
```

### 5. Validate subnet IP availability

```powershell
cd ..
.\.venv\Scripts\python.exe python/scripts/validate_subnet_ips.py terraform/tfplan.json subnet-0123456789abcdef0
```

### 5a. Simulate failure with a lower available IP count

```powershell
cd ..
.\.venv\Scripts\python.exe python/scripts/validate_subnet_ips.py terraform/tfplan.json subnet-0123456789abcdef0 --override-available-ips=1
```

This forces the validator to fail even if the real subnet has more IPs.

### 5b. Simulate failure by overriding required IPs

```powershell
cd ..
.\.venv\Scripts\python.exe python/scripts/validate_subnet_ips.py terraform/tfplan.json subnet-0123456789abcdef0 --override-required-ips=10
```

This forces the validator to treat the plan as if it needs more IPs than it actually does.

### 6. Apply Terraform if validation passes

```powershell
cd terraform
terraform apply -auto-approve tfplan
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

Optional simulation inputs:

- `test_fail_deployment` — set to `true` to enable a subnet CIDR reservation and simulate IP exhaustion during deployment

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

Optional failure simulation:

```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-0123456789abcdef0 `
  --field subnet_id=subnet-0123456789abcdef0 `
  --field test_fail_deployment=true
```

## Destroy from GitHub Actions

A separate workflow is available for teardown after deployment. In the GitHub UI, run `Destroy Ephemeral Environment` and provide the same `env_name`, `vpc_id`, and `subnet_id` values used for deployment.

From GitHub CLI:

```powershell
gh workflow run ephemeral-destroy.yml `
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
- If the workflow fails due to validation, Terraform apply is skipped and no new resources are created.
- This behavior prevents bad deployments and avoids consuming subnet capacity.
- Stale resources from previous runs are not cleaned by this preflight check; they are handled separately by the cleanup/janitor logic after resources already exist.
- If validation fails, the project still benefits by stopping the deployment before any new infrastructure is provisioned.
