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
  - `pwsh` or `powershell` on Windows
  - `bash` / `zsh` on macOS/Linux
- Python 3.11 installed
  - `python --version`
- Terraform installed and on PATH
  - `terraform version`
- AWS CLI installed and configured with valid credentials
  - `aws --version`
  - `aws configure`
- An existing AWS VPC ID and Subnet ID
  - `aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output table`
  - `aws ec2 describe-subnets --query 'Subnets[*].{Id:SubnetId,Vpc:VpcId,Cidr:CidrBlock,Available:AvailableIpAddressCount}' --output table`
  - Note: the GitHub workflow supports `test_fail_deployment=true` to simulate subnet IP exhaustion; leave it false for normal deployment.
- An existing S3 bucket for Terraform remote state
  - `aws s3api head-bucket --bucket your-bucket-name`
- GitHub repository secrets configured for AWS credentials when using GitHub Actions
  - `gh secret set AWS_ACCESS_KEY_ID`
  - `gh secret set AWS_SECRET_ACCESS_KEY`

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

## Deployment from Terraform - Simulating Insufficient IP Address

### 1. Initialize Terraform with S3 backend

```powershell
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate" -reconfigure
```

> The S3 bucket must already exist and is configured in `terraform/main.tf`.

### 2. Create a Terraform plan, Simulating Insufficient IP Address

```powershell
terraform plan `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-1c9e8167" `
  -var="subnet_id=subnet-24ef3243" `
  -var="enable_subnet_reservation=true" `
  -out="tfplan"
```

### 3. Export plan to JSON

```powershell
terraform show -json tfplan > tfplan.json
```

### 4. Validate subnet IP availability

```powershell
cd ..
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243
```

### 5a. Simulate failure with a lower available IP count

```powershell
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243 --override-available-ips=1
```

### 5b. Simulate failure by overriding required IPs

```powershell
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243 --override-required-ips=10
```

### 6. Apply Terraform, Simulating Insufficient IP Address, to fail the deployment.

```powershell
terraform apply `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-1c9e8167" `
  -var="subnet_id=subnet-24ef3243" `
  -var="enable_subnet_reservation=true" `
  -auto-approve tfplan
```

> No need for Terraform Destroy, as deployment has not happened only.


## Deployment from Terraform

### 1. Initialize Terraform with S3 backend

```powershell
cd terraform
terraform init -backend-config="key=ephemeral/dev/terraform.tfstate" -reconfigure
```

> The S3 bucket must already exist and is configured in `terraform/main.tf`.

### 2. Create a Terraform plan

```powershell
terraform plan `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-1c9e8167" `
  -var="subnet_id=subnet-24ef3243" `
  -var="enable_subnet_reservation=false" `
  -out="tfplan"
```

### 3. Export plan to JSON

```powershell
terraform show -json tfplan > tfplan.json
```

### 4. Validate subnet IP availability

```powershell
cd ..
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243
```

### 5a. Simulate failure with a lower available IP count

```powershell
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243 --override-available-ips=1
```

### 5b. Simulate failure by overriding required IPs

```powershell
python .\python\scripts\validate_subnet_ips.py terraform\tfplan.json subnet-24ef3243 --override-required-ips=10
```

### 6. Apply Terraform

```powershell
terraform apply `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-1c9e8167" `
  -var="subnet_id=subnet-24ef3243" `
  -var="enable_subnet_reservation=false" `
  -auto-approve tfplan
```

### 7. Destroy Terraform
```powershell
terraform destroy `
  -var="environment_name=dev" `
  -var="vpc_id=vpc-1c9e8167" `
  -var="subnet_id=subnet-24ef3243" `
  -var="enable_subnet_reservation=false"
```


## Configuration for GitHub Actions (UI and CLI)

### 1. GitHub secrets required

Add the following secrets to your GitHub repository:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### 2. Workflow inputs

The workflow defined in `.github/workflows/ephemeral-pipeline.yml` requires:

- `env_name` — environment name (for state key and tags)
- `vpc_id` — existing VPC ID
- `subnet_id` — existing Subnet ID

Optional simulation inputs:

- `test_fail_deployment` — set to `true` to enable a subnet CIDR reservation and simulate IP exhaustion during deployment
- `destroy` — set to `true` to destroy the deployed environment

## Deployment from GitHub Actions (UI and CLI)
### 1. Deploy via GitHub UI
1. Go to the `Actions` tab in your GitHub repository.
2. Select `Ephemeral Environment Pipeline`.
3. Click `Run workflow`.
4. Enter values for `env_name`, `vpc_id`, and `subnet_id`.
5. Enter `false` for `test_fail_deployment` Since we dont want to enable subnet CIDR reservation to simulate IP exhaustion.
6. Enter `false` for `destroy` Since we are deploying.
7. Run the workflow.

### 2. Destroy from GitHub UI
1. Go to the `Actions` tab in your GitHub repository.
2. Select `Ephemeral Environment Pipeline`.
3. Click `Run workflow`.
4. Enter values for `env_name`, `vpc_id`, and `subnet_id`.
5. Enter `true` for `destroy` if you want to destroy the deployed environment.
7. Run the workflow.


### 3. Deploy via GitHub CLI
```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-1c9e8167 `
  --field subnet_id=subnet-24ef3243

To verify the execution:
gh run list --workflow="ephemeral-pipeline.yml"  
```

### 4. Destroy via GitHub CLI
```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-1c9e8167 `
  --field subnet_id=subnet-24ef3243 `
  --field destroy=true

To verify the execution:
gh run list --workflow="ephemeral-pipeline.yml"  
```

## Simulate Insufficient IP Address, Deployment from GitHub Actions (UI and CLI)
### 1. Deploy via GitHub UI
1. Go to the `Actions` tab in your GitHub repository.
2. Select `Ephemeral Environment Pipeline`.
3. Click `Run workflow`.
4. Enter values for `env_name`, `vpc_id`, and `subnet_id`.
5. Enter `true` for `test_fail_deployment` if you want to enable subnet CIDR reservation to simulate IP exhaustion.
6. Run the workflow.

### 2. Deploy via GitHub UI
```powershell
gh workflow run ephemeral-pipeline.yml `
  --field env_name=dev `
  --field vpc_id=vpc-1c9e8167 `
  --field subnet_id=subnet-24ef3243 `
  --field test_fail_deployment=true

To verify the execution:
gh run list --workflow="ephemeral-pipeline.yml"

NOTE: No need to DESTROY, as DEPLOYMENT hasn not happened.
```


## AWS verification commands (Without Simulation)

After deployment, use these commands to verify resources.

### Check the subnet

```powershell
aws ec2 describe-subnets `
  --subnet-ids subnet-24ef3243 `
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
- Please delete any left over resources, post destroying environment.
- EBS volume are configured with detele protection, so thay are expected to stay back, delete it through console or cli.
