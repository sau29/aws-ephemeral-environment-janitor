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

## High-Level Architectural Overview

                  +-----------------------------------+
                  |      GitHub Actions Workflow      |
                  |    (ephemeral-pipeline.yml)       |
                  +-----------------+-----------------+
                                    |
                             1. Terraform Plan
                                    |
                                    v
                   +---------------------------------+
                   |    validate_subnet_ips.py       |
                   |    (Preflight Capacity Check)   |
                   +----------------+----------------+
                                    |
                  +-----------------+-----------------+
                  |                                   |
          [ PASS: Sufficient IPs ]           [ FAIL: IP Exhaustion ]
                  |                                   |
                  v                                   v
      +-----------------------+           +-----------------------+
      |    Terraform Apply    |           |   Abort Deployment    |
      |  (Deploy EC2 + SGs)   |           | (No Infrastructure)   |
      +-----------+-----------+           +-----------------------+
                  |
                  v
      +-----------------------+
      |    Janitor Lambda     |
      |  (Cleanup Engine)     |
      +-----------------------+


## Core Components

1. **Infrastructure Provisioning (`terraform/`)**
* **`main.tf`**: Uses an existing VPC and Subnet to launch EC2 instances (`t2.micro`) and security groups. Includes a configurable subnet CIDR reservation flag (`enable_subnet_reservation`) to simulate IP exhaustion scenarios.
* **`janitor_lambda.tf`**: Configures an IAM role, policies, and a Python 3.11 Lambda function (`janitor-engine`) to clean detached resources.
* **`variables.tf`**: Input configuration for AWS region, environment name, VPC ID, and Subnet ID.


2. **Validation & Cleanup Engine (`python/`)**
* **`validate_subnet_ips.py`**: A preflight script that parses the `terraform show -json` execution plan, counts required IP address creations, queries Boto3 for available IPs on the target subnet, and aborts deployment if capacity is insufficient.
* **`janitor_engine.py`**: Lambda execution handler (`lambda_handler`) that identifies and deletes unattached EBS volumes and network interfaces tagged with `Ephemeral=true`.


3. **CI/CD Automation (`.github/workflows/`)**
* **`ephemeral-pipeline.yml`**: GitHub Actions pipeline that automates `terraform init`, `terraform plan`, JSON conversion, `validate_subnet_ips.py` preflight check, and `terraform apply`/`destroy`.


## Prerequisites

* **Python**: 3.11+
* **Terraform**: `>= 1.0`
* **AWS CLI**: Installed and configured
* **AWS Account Setup**: An existing VPC ID, Subnet ID, and pre-created S3 Bucket for Terraform remote state (`aws-ephemeral-environment-janitor-state`).

## Notes

- The code now uses an existing VPC and Subnet rather than creating new networking.
- The subnet validation step uses `validate_subnet_ips.py` and an AWS `describe_subnets` call.
- If the workflow fails due to validation, Terraform apply is skipped and no new resources are created.
- This behavior prevents bad deployments and avoids consuming subnet capacity.
- Stale resources from previous runs are not cleaned by this preflight check; they are handled separately by the cleanup/janitor logic after resources already exist.
- If validation fails, the project still benefits by stopping the deployment before any new infrastructure is provisioned.
