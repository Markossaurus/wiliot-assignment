# Binance trades → Kafka → PostgreSQL on EKS

Live Binance trades are ingested over WebSocket, published to Kafka, and landed exactly once per `(symbol, trade_id)` in PostgreSQL. Everything runs on EKS in `eu-central-1` and is provisioned with Terraform.

> Work in progress. Sections below are filled in as each phase lands.

## Health check

_TBD_

## Deploy

_TBD_

## Destroy

_TBD_

## Evidence

_TBD_

## Assumptions and shortcuts

_TBD_

## Development

Enable the repo's git hooks once per clone (secret scan with gitleaks, `terraform fmt` check):

```sh
git config core.hooksPath .githooks
```
