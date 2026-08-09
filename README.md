# aws-ephemeral-environment-janitor (local workspace)

This workspace contains scaffolding for the AWS Ephemeral Environment Janitor lab.

Structure:

- terraform/: Terraform IaC
- python/: Python automation scripts and unit tests
- .github/workflows/: CI workflows

Quickstart (Windows PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\pip.exe install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest -q
```

Terraform backend note:

- The S3 state bucket must already exist before running `terraform init`.
- The workflow passes the state key dynamically via `-backend-config="key=..."`.
- Backend configuration cannot reference normal variables like `var.aws_region`.
