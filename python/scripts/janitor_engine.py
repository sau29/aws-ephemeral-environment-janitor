import logging
from typing import Any, Dict, List

import boto3
from botocore.exceptions import BotoCoreError, ClientError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("janitor_engine")


def _get_ec2_client():
    return boto3.client("ec2")


def _find_ephemeral_volumes(ec2_client, environment_name: str) -> List[Dict[str, Any]]:
    paginator = ec2_client.get_paginator("describe_volumes")
    filters = [
        {"Name": "status", "Values": ["available"]},
        {"Name": "tag:Environment", "Values": [environment_name]},
        {"Name": "tag:Ephemeral", "Values": ["true"]},
    ]

    volumes = []
    for page in paginator.paginate(Filters=filters):
        volumes.extend(page.get("Volumes", []))

    return volumes


def _delete_volumes(ec2_client, volumes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    deleted = []
    for volume in volumes:
        volume_id = volume.get("VolumeId")
        size = volume.get("Size")
        logger.info(
            "Found orphaned EBS volume",
            extra={"volume_id": volume_id, "size_gb": size, "environment": True},
        )
        try:
            ec2_client.delete_volume(VolumeId=volume_id)
            logger.info(
                "Deleted EBS volume",
                extra={"volume_id": volume_id, "size_gb": size},
            )
            deleted.append({"VolumeId": volume_id, "Size": size})
        except (BotoCoreError, ClientError) as exc:
            logger.exception(
                "Failed to delete EBS volume",
                extra={"volume_id": volume_id, "error": str(exc)},
            )
    return deleted


def _find_security_group_ids(ec2_client, environment_name: str) -> List[str]:
    response = ec2_client.describe_security_groups(
        Filters=[{"Name": "tag:Environment", "Values": [environment_name]}]
    )
    sg_ids = [sg["GroupId"] for sg in response.get("SecurityGroups", [])]
    logger.info(
        "Environment security groups discovered",
        extra={"environment": environment_name, "security_group_ids": sg_ids},
    )
    return sg_ids


def _find_enis_for_security_groups(
    ec2_client, security_group_ids: List[str]
) -> List[Dict[str, Any]]:
    if not security_group_ids:
        return []

    filters = [{"Name": "group-id", "Values": security_group_ids}]
    response = ec2_client.describe_network_interfaces(Filters=filters)
    enis = response.get("NetworkInterfaces", [])
    logger.info(
        "Found network interfaces attached to environment security groups",
        extra={"eni_count": len(enis), "security_group_ids": security_group_ids},
    )
    return enis


def _detach_and_delete_enis(
    ec2_client, enis: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    deleted = []
    for eni in enis:
        eni_id = eni.get("NetworkInterfaceId")
        status = eni.get("Status")
        attachment = eni.get("Attachment")

        logger.info(
            "Processing ENI",
            extra={"eni_id": eni_id, "status": status, "attachment": bool(attachment)},
        )

        if status == "in-use" and attachment:
            attachment_id = attachment.get("AttachmentId")
            try:
                ec2_client.detach_network_interface(
                    AttachmentId=attachment_id, Force=True
                )
                logger.info(
                    "Force-detached ENI attachment",
                    extra={"eni_id": eni_id, "attachment_id": attachment_id},
                )
            except (BotoCoreError, ClientError) as exc:
                logger.exception(
                    "Failed to detach ENI",
                    extra={
                        "eni_id": eni_id,
                        "attachment_id": attachment_id,
                        "error": str(exc),
                    },
                )
                continue

        try:
            ec2_client.delete_network_interface(NetworkInterfaceId=eni_id)
            logger.info(
                "Deleted ENI",
                extra={"eni_id": eni_id, "status": status},
            )
            deleted.append({"NetworkInterfaceId": eni_id, "Status": status})
        except (BotoCoreError, ClientError) as exc:
            logger.exception(
                "Failed to delete ENI",
                extra={"eni_id": eni_id, "error": str(exc)},
            )
    return deleted


def lambda_handler(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    environment_name = event.get("environment_name")
    if not environment_name:
        message = "Missing required parameter: environment_name"
        logger.error(message)
        raise ValueError(message)

    logger.info(
        "Starting ephemeral environment cleanup",
        extra={"environment_name": environment_name},
    )

    ec2_client = _get_ec2_client()

    volumes = _find_ephemeral_volumes(ec2_client, environment_name)
    deleted_volumes = _delete_volumes(ec2_client, volumes)

    security_group_ids = _find_security_group_ids(ec2_client, environment_name)
    enis = _find_enis_for_security_groups(ec2_client, security_group_ids)
    deleted_enis = _detach_and_delete_enis(ec2_client, enis)

    result = {
        "environment_name": environment_name,
        "deleted_volumes": len(deleted_volumes),
        "deleted_volume_details": deleted_volumes,
        "deleted_enis": len(deleted_enis),
        "deleted_eni_details": deleted_enis,
    }

    logger.info(
        "Ephemeral environment cleanup complete",
        extra={
            "environment_name": environment_name,
            "deleted_volumes": len(deleted_volumes),
            "deleted_enis": len(deleted_enis),
        },
    )
    return result
