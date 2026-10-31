"""Writes Flyway's connection settings for the RDS master user.

Runs as the init container of the database migration Job. RDS names the master secret itself, so
it is found through the instance. The password only lands in the Job's in-memory volume.
"""

import json
import logging
import os
import shutil
from pathlib import Path

import boto3

log = logging.getLogger("db_bootstrap")

# Baked into the image by the Dockerfile.
RDS_CA_BUNDLE = Path("/etc/ssl/certs/rds-global-bundle.pem")


def flyway_config(instance: dict, credentials: dict, ssl_root_cert: str) -> str:
    endpoint = instance["Endpoint"]
    url = (
        f"jdbc:postgresql://{endpoint['Address']}:{endpoint['Port']}/{instance['DBName']}"
        f"?sslmode=verify-full&sslrootcert={ssl_root_cert}"
    )
    # A JSON string is also a valid TOML basic string, so json.dumps quotes and escapes safely.
    return "\n".join(
        [
            "[environments.rds]",
            f"url = {json.dumps(url)}",
            f"user = {json.dumps(credentials['username'])}",
            f"password = {json.dumps(credentials['password'])}",
            "",
            "[flyway]",
            'environment = "rds"',
            "",
        ]
    )


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    region = os.environ["AWS_REGION"]
    instance_id = os.environ["DB_INSTANCE_IDENTIFIER"]
    instance = boto3.client("rds", region_name=region).describe_db_instances(DBInstanceIdentifier=instance_id)[
        "DBInstances"
    ][0]
    secret = boto3.client("secretsmanager", region_name=region).get_secret_value(
        SecretId=instance["MasterUserSecret"]["SecretArn"]
    )
    path = Path(os.environ["FLYWAY_CONFIG_FILE"])
    # Flyway runs from its own image, so the CA bundle travels next to the settings.
    ca_bundle = path.with_name(RDS_CA_BUNDLE.name)
    shutil.copyfile(RDS_CA_BUNDLE, ca_bundle)
    path.write_text(flyway_config(instance, json.loads(secret["SecretString"]), str(ca_bundle)))
    path.chmod(0o400)
    log.info("wrote Flyway settings for %s to %s", instance_id, path)


if __name__ == "__main__":
    main()
