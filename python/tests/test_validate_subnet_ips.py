import json
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

import python.scripts.validate_subnet_ips as validate


def write_tfplan_file(path: Path, required_resources: int) -> Path:
    plan = {
        "resource_changes": [
            {"type": "aws_instance", "change": {"actions": ["create"]}}
            for _ in range(required_resources)
        ]
    }
    path.write_text(json.dumps(plan), encoding="utf-8")
    return path


def write_tfplan_file_bytes(path: Path, data: bytes) -> Path:
    path.write_bytes(data)
    return path


def create_test_subnet():
    ec2 = boto3.client("ec2", region_name="us-east-1")
    vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")
    subnet = ec2.create_subnet(VpcId=vpc["Vpc"]["VpcId"], CidrBlock="10.0.0.0/28")
    return subnet["Subnet"]["SubnetId"]


class PatchedEC2Client:
    def __init__(self, wrapped_client, available_ip_count: int):
        self._wrapped = wrapped_client
        self._available_ip_count = available_ip_count

    def describe_subnets(self, SubnetIds=None, **kwargs):
        response = self._wrapped.describe_subnets(SubnetIds=SubnetIds, **kwargs)
        for subnet in response.get("Subnets", []):
            subnet["AvailableIpAddressCount"] = self._available_ip_count
        return response

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def run_script(
    monkeypatch, capsys, plan_file: Path, subnet_id: str, available_ips: int
):
    original_client = boto3.client

    def patched_client(service_name, *args, **kwargs):
        if service_name == "ec2":
            client = original_client(
                service_name, region_name="us-east-1", *args, **kwargs
            )
            return PatchedEC2Client(client, available_ips)
        return original_client(service_name, *args, **kwargs)

    monkeypatch.setattr(validate.boto3, "client", patched_client)
    monkeypatch.setattr(
        sys, "argv", ["validate_subnet_ips.py", str(plan_file), subnet_id]
    )

    exit_code = validate.main()
    captured = capsys.readouterr()
    return exit_code, captured


@mock_aws
def test_validate_subnet_ips_pass(monkeypatch, capsys, tmp_path):
    plan_file = write_tfplan_file(tmp_path / "tfplan.json", required_resources=2)
    subnet_id = create_test_subnet()

    exit_code, captured = run_script(
        monkeypatch, capsys, plan_file, subnet_id, available_ips=5
    )

    assert exit_code == 0
    assert "test_validate_subnet_ips_pass - PASS: subnet has sufficient available private IP addresses." in captured.out
    assert "RequiredIPs=2" in captured.out
    assert "AvailableIPs=5" in captured.out


@mock_aws
def test_load_tfplan_utf16_file(tmp_path):
    plan = {"resource_changes": [{"type": "aws_instance", "change": {"actions": ["create"]}}]}
    path = tmp_path / "tfplan.json"
    write_tfplan_file_bytes(path, json.dumps(plan).encode("utf-16"))

    loaded = validate.load_tfplan(path)

    assert loaded == plan


@mock_aws
def test_validate_subnet_ips_fail(monkeypatch, capsys, tmp_path):
    plan_file = write_tfplan_file(tmp_path / "tfplan.json", required_resources=3)
    subnet_id = create_test_subnet()

    exit_code, captured = run_script(
        monkeypatch, capsys, plan_file, subnet_id, available_ips=2
    )

    assert exit_code == 1
    assert "FAILURE: insufficient available private IP addresses." in captured.out
    assert "RequiredIPs=3" in captured.out
    assert "AvailableIPs=2" in captured.out
    assert "Deficit=1" in captured.out
