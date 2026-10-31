import tomllib

from db_bootstrap import flyway_config

INSTANCE = {
    "Endpoint": {"Address": "db.example.eu-central-1.rds.amazonaws.com", "Port": 5432},
    "DBName": "trades",
}


def test_config_selects_the_rds_environment_with_verified_tls():
    config = tomllib.loads(flyway_config(INSTANCE, {"username": "postgres", "password": "pw"}, "/ca.pem"))
    assert config["flyway"]["environment"] == "rds"
    assert config["environments"]["rds"]["url"] == (
        "jdbc:postgresql://db.example.eu-central-1.rds.amazonaws.com:5432/trades"
        "?sslmode=verify-full&sslrootcert=/ca.pem"
    )


def test_password_survives_toml_special_characters():
    password = 'a"b\\c#d$e{f}\'g\nh'
    config = tomllib.loads(flyway_config(INSTANCE, {"username": "postgres", "password": password}, "/ca.pem"))
    assert config["environments"]["rds"]["user"] == "postgres"
    assert config["environments"]["rds"]["password"] == password
