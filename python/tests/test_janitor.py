from moto import mock_aws
import boto3

from python.scripts.janitor import clean_ephemeral_resources


@mock_aws
def test_clean_ephemeral_resources_no_errors():
    # basic smoke test that function runs against mocked AWS
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="test-bucket")

    # call the function to ensure no exceptions are raised
    clean_ephemeral_resources()

    # verify mocked bucket still exists (placeholder assertion)
    buckets = s3.list_buckets()["Buckets"]
    assert any(b["Name"] == "test-bucket" for b in buckets)
