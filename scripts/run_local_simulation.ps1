Param(
    [Parameter(Mandatory=$true)][string]$SubnetId,
    [string]$BackendKey = "local-simulation.tfstate",
    [string]$EnvironmentName = "dev"
)

# Change to repo root (script lives in scripts/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $ScriptDir "..")

$TF_PLAN = "tfplan"
$TF_PLAN_JSON = "tfplan.json"

# Find Python in venv or PATH
if (Test-Path ".\.venv\Scripts\python.exe") {
    $Python = ".\.venv\Scripts\python.exe"
} elseif (Test-Path ".\.venv\bin\python") {
    $Python = ".\.venv\bin\python"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $Python = "python"
} else {
    Write-Error "Python executable not found. Activate or create .venv first or have python on PATH."
    exit 1
}

Write-Host "=== Terraform init ==="
terraform init -backend-config="key=$BackendKey"

Write-Host "=== Terraform plan ==="
terraform plan -var="environment_name=$EnvironmentName" -out=$TF_PLAN

Write-Host "=== Terraform show JSON (write as UTF-8) ==="
# PowerShell's redirection/Out-File defaults to UTF-16; capture and write UTF-8 explicitly
$planText = & terraform show -json $TF_PLAN
$planText | Out-File -FilePath $TF_PLAN_JSON -Encoding utf8

Write-Host "=== Validate subnet IPs ==="
$extraArgs = @()
# call the validator
& $Python ".\python\scripts\validate_subnet_ips.py" ".\terraform\$TF_PLAN_JSON" $SubnetId @extraArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Subnet IP validation failed as expected. Continuing to failure simulation."
} else {
    Write-Error "ERROR: Subnet IP validation unexpectedly passed."
    exit 1
}

Write-Host "=== Terraform apply (expected partial failure due to IP exhaustion) ==="
$env:TF_IN_AUTOMATION = "1"
$applyProcess = Start-Process terraform -ArgumentList "apply -auto-approve $TF_PLAN" -Wait -PassThru
if ($applyProcess.ExitCode -eq 0) {
    Write-Warning "Terraform apply succeeded unexpectedly. The failure simulation may not be valid."
} else {
    Write-Host "Terraform apply failed as expected with exit code $($applyProcess.ExitCode)."
}

Write-Host "=== Terraform destroy ==="
try {
    terraform destroy -var="environment_name=$EnvironmentName" -auto-approve
} catch {
    Write-Warning "Destroy failed or nothing to destroy."
}

Write-Host "=== Local simulation complete. ==="
exit 0
