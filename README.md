# Binance trades → Kafka → PostgreSQL on EKS

Live Binance trades are streamed over WebSocket into Kafka (Amazon MSK) and land in PostgreSQL (Amazon RDS) exactly once per `(symbol, trade_id)`. The producer and consumer run on EKS in `eu-central-1`, deployed by Argo CD from this repo. Everything is provisioned with Terraform through Terragrunt. The stack is left running in the sandbox account.

```
 Binance WebSocket ──► producer ×3 ──► MSK topic ──► consumer ×3–6 ──► RDS PostgreSQL
                       one per AZ,     binance.trades  KEDA on lag,      trades: PK (symbol, trade_id)
                       every symbol    6 partitions    INSERT … ON CONFLICT DO NOTHING
                                                                          │
 Binance REST ──► backfill (every 5 min) ──► same topic                  │
                    │ keeps per-symbol watermarks ◄───── reads ───────────┤
                    ▼                                                     │
              trade_watermarks ◄─── reads ─── data probe (every minute) ◄─┘
                                                │
                                                ▼
                        CloudWatch metrics ─► 4 alarms ─► 1 composite health alarm ─► SNS
```

## Health check

```sh
aws cloudwatch describe-alarms --region eu-central-1 --alarm-types CompositeAlarm \
  --alarm-names alarm-trades-health-euc1-prod --query 'CompositeAlarms[0].StateValue' --output text
```

`OK` means healthy. The composite alarm is `ALARM` while any of these is: trades stopped landing (staleness), the freshness target is missed, trades are missing and not yet backfilled (completeness), or the consumer group is falling behind (lag). The dashboard `dashboard-trades-euc1-prod` shows the same signals.

## Freshness target

**p99 of (row in PostgreSQL − trade executed on Binance) ≤ 1 s**, measured every minute from the table itself. Steady state is about 0.23–0.28 s.

| Alarm | Fires when | Why this threshold |
|---|---|---|
| freshness | p99 above 1 s for 5 consecutive minutes | A rolling restart costs one slow minute (see evidence); a sustained miss is what matters. |
| staleness | no trade landed for 60 s, 3 minutes in a row; missing data counts as breaching | BTCUSDT alone trades many times a second, so a minute of silence is an outage. If the probe itself stops, this fires too. |
| completeness | any trade ID missing and not yet backfilled | Binance trade IDs increase by one per symbol, so a gap is a lost trade. |
| consumer lag | MSK's broker-side `EstimatedMaxTimeLag` above 30 s for 3 minutes | Measured by the brokers, so it holds even if the consumer can't report about itself. |

## Deploy

Prerequisites: Terraform ≥ 1.10, Terragrunt 1.x, the AWS CLI with the sandbox credentials, and `gh` for the CI step.

```sh
cd live/prod/eu-central-1
terragrunt run --all apply
gh workflow run build.yml   # only after a fresh apply: ECR starts empty
```

- Terragrunt applies the units in dependency order: `vpc` and `ecr` first, then `eks`, then `msk`, `rds` and `argocd`, then `iam` and `monitoring`.
- The `argocd` unit bootstraps Argo CD from a one-shot instance inside the VPC (see [Delivery](#delivery)). From then on, Argo CD deploys everything else from `argocd/` in this repo.
- The workflow rebuilds the images and charts.

## Destroy

```sh
cd live/prod/eu-central-1
terragrunt run --all destroy
```

It needs only AWS credentials, no access to the cluster.

## Evidence

Every minute, the data probe measures the `trades` table and publishes the results to CloudWatch. The checks below re-read those measurements, so anyone with read access to the account can re-run them:

```sh
metric() { aws cloudwatch get-metric-statistics --region eu-central-1 --namespace Trades --metric-name "$1" \
  --start-time "$2" --end-time "$3" --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' --output text; }
```

Outputs are trimmed to the minutes that matter, with long decimals shortened, and shown in UTC; the CLI prints your local zone unless you set `TZ=UTC`. CloudWatch keeps 1-minute data for 15 days; after that, use `--period 300`.

**Freshness stays well under the 1 s target.**
```sh
metric IngestLatencyP99 2026-10-31T20:05:00Z 2026-10-31T20:15:00Z
```
```
2026-10-31T20:05:00+00:00  0.279444
2026-10-31T20:06:00+00:00  0.232773
…
2026-10-31T20:14:00+00:00  0.239083
```
Every minute's p99, from the trade on Binance to its row in PostgreSQL, was between 0.23 and 0.28 s.

**The consumer keeps processing through a restart.** Rolling out `cf63169` changed the consumer's pod template, so all three pods were replaced at 17:35.
```sh
metric IngestLatencyP99 2026-10-31T17:34:00Z 2026-10-31T17:39:00Z
```
```
2026-10-31T17:34:00+00:00  0.227641
2026-10-31T17:35:00+00:00  0.233099
2026-10-31T17:36:00+00:00  3.106873
2026-10-31T17:37:00+00:00  0.247682
2026-10-31T17:38:00+00:00  0.234347
```
p99 rose to 3.1 s for the one minute the pods rolled, then went straight back. `MissingTrades` stayed 0, and `SecondsSinceLastTrade` never exceeded 0.47 s, so trades kept landing throughout. The freshness alarm stayed OK, since it needs 5 slow minutes.

**The consumer keeps processing through scaling.** `318cd9c` raised the autoscaler's minimum from 3 to 6 consumers, and `f19abb3` set it back to 3.
```sh
metric IngestLatencyP99 2026-10-31T22:34:00Z 2026-10-31T22:40:00Z
```
```
2026-10-31T22:34:00+00:00  0.235643
2026-10-31T22:35:00+00:00  0.23046
2026-10-31T22:36:00+00:00  0.269599
2026-10-31T22:37:00+00:00  0.26128
2026-10-31T22:38:00+00:00  0.24573
2026-10-31T22:39:00+00:00  0.231418
```
The consumers scaled from 3 to 6 at 22:35:36 and back to 3 at 22:38:26. Each time, the rebalance moved only the partitions that changed owner, in about 2 s: the consumers' logs show each new pod taking one partition, then the three remaining pods taking them back. Through both, p99 stayed between 0.23 and 0.27 s, and `MissingTrades` was 0 every minute.

**Losing every connection: the gap is detected and repaired.** `524bdb5` scaled the producers to 0, and `4ec1ed9` restored them. No trade landed for about 9 minutes.
```sh
metric MissingTrades 2026-10-31T20:25:00Z 2026-10-31T20:32:00Z
```
```
2026-10-31T20:25:00+00:00  0.0
2026-10-31T20:26:00+00:00  13063.0
2026-10-31T20:27:00+00:00  13278.0
2026-10-31T20:28:00+00:00  13278.0
2026-10-31T20:29:00+00:00  13278.0
2026-10-31T20:30:00+00:00  9770.0
2026-10-31T20:31:00+00:00  0.0
```
Once trades resumed, the probe counted the gap: 13,278 trades across all 9 symbols. The backfill's 20:30 run fetched them from Binance's REST API, and a minute later nothing was missing. During the outage, `SecondsSinceLastTrade` climbed to 480 s, and the staleness alarm fired.

**A gap stays reported until it is filled.** `732f493` paused the backfill and stopped the producers, `9770048` brought the producers back, and `b64c7b7` resumed the backfill.
```sh
metric MissingTrades 2026-10-31T20:44:00Z 2026-10-31T21:02:00Z
```
```
2026-10-31T20:44:00+00:00  0.0
2026-10-31T20:45:00+00:00  8220.0
…                          8220.0 every minute
2026-10-31T20:59:00+00:00  8220.0
2026-10-31T21:00:00+00:00  6266.0
2026-10-31T21:01:00+00:00  0.0
```
With nothing repairing it, the gap stayed counted, and the completeness alarm raised, for 15 minutes. Only the backfill's repair cleared it.

**No duplicates, by construction.**
```sh
grep -n "PRIMARY KEY" charts/database/files/migrations/V1__create_trades.sql; grep -n "ON CONFLICT" apps/consumer/consumer.py
```
```
10:    PRIMARY KEY (symbol, trade_id)
33:ON CONFLICT (symbol, trade_id) DO NOTHING
```
Every trade reaches Kafka about three times, once from each producer, and the backfill overlaps the stream on purpose. The primary key stores each trade once, and a repeated insert is a no-op.

**A clean destroy, and a fresh deploy from nothing.**
```sh
cd live/prod/eu-central-1 && terragrunt run --all destroy
```
```
[monitoring] Destroy complete! Resources: 7 destroyed.
[iam] Destroy complete! Resources: 16 destroyed.
[argocd] Destroy complete! Resources: 10 destroyed.
[ecr] Destroy complete! Resources: 16 destroyed.
[msk] Destroy complete! Resources: 9 destroyed.
[rds] Destroy complete! Resources: 7 destroyed.
[eks] Destroy complete! Resources: 43 destroyed.
[vpc] Destroy complete! Resources: 32 destroyed.
```
Nothing of the stack was left in the account. `terragrunt run --all apply` then rebuilt all 140 resources and one CI run the images, Flyway applied V1–V4 to the new database, and the health check returned `OK`.

## Design decisions

### Kafka: MSK provisioned, 3× `kafka.t3.small`

- **Why not Kafka on EKS (e.g. Strimzi)?**
  - **A clean destroy.** Brokers on EKS keep their data on EBS volumes created from inside the cluster. A Terraform destroy deletes the cluster without deleting those volumes, so they're orphaned and keep billing. Avoiding that would need an ordered teardown with cluster access, which is closed off.
  - **No Kafka credentials.** MSK IAM auth plus IRSA gives each workload exactly the topic and group actions it needs: the producer writes, the consumer reads in its group, KEDA only describes. Self-hosted would mean SCRAM passwords or mTLS certificates to issue and rotate, plus Kafka ACLs alongside IAM.
  - **Nothing to operate.** AWS replaces failed brokers with the same ID and storage, patches them, and runs ZooKeeper.
- **Trade-offs I accepted:**
  - t3 brokers are burstable and positioned for dev and test.
  - They can't run KRaft, so the cluster runs Kafka 3.9.x, the last release with ZooKeeper.
- **Topic:** `binance.trades`, created by Terraform: 6 partitions, replication factor 3, `min.insync.replicas` 2, 7-day retention. The producers keep writing while AWS patches one broker at a time.

### PostgreSQL: RDS, `db.t4g.medium`, single-AZ

- **Why not in the cluster?** The same clean-destroy reason as Kafka, plus a master password that RDS manages in Secrets Manager, so it never reaches Terraform state.
- **No passwords for the apps.** They log in with IAM database authentication and verify the server certificate.
- **Why single-AZ?** Cost. Kafka retains 7 days, and the consumer commits offsets only after its database commit, so a database outage delays rows but loses none.
- **Least privilege per user:**
  - `trades_writer` (the consumer) can only `SELECT` and `INSERT`, so nobody can change or delete a trade once written.
  - `trades_reader` (the probe) is read-only.
  - `trades_backfill` reads trades and keeps the watermarks, but can't write trades.
- **Schema:**
  - Besides the spec's columns, `ingested_at` records when each row landed; freshness is measured from it.
  - `notional` always equals `price * quantity` exactly.
  - Migrations are Flyway files in `charts/database`; see [Database migrations](#database-migrations-part-of-the-consumers-release-specific-on-purpose).

### Database migrations: part of the consumer's release, specific on purpose

- **Part of the service.** The consumer is the only writer of `trades`, so its Argo CD Application carries the database chart too:
  - Flyway runs in an earlier sync wave of the same sync, so the schema is in place before the code that needs it rolls out.
  - A failed migration stops the rollout.
  - A migration and the code it serves are reviewed and versioned together.
  - The database is one history: the same chart also creates the probe's and the backfill's users and the watermarks table.
- **Not a generic migration runner, on purpose.** With one service, a generic chart's contract would be guesses:
  - where the migrations come from;
  - a database or schema per service;
  - how it authenticates;
  - which Flyway options, timeouts and naming it takes.

  Each guess would be a parameter nothing uses yet. I'd generalize from the 2nd service.
- **What it would become with more services:**
  - a migration-runner chart fed by each service's own migrations and values;
  - each service migrating as its own IAM-authenticated migrator role;
  - a codified platform step that creates each database and its roles, the only step that needs the master password. That would be Terraform's `postgresql` provider, run from inside the VPC.
- **Credentials today.** The Job connects as the RDS master user. Its password goes from Secrets Manager into an in-memory volume for the Job's lifetime and never becomes a Kubernetes Secret.

### Exactly once per `(symbol, trade_id)`

- The primary key decides what's a duplicate, so correctness doesn't depend on how many times a message is delivered.
- The consumer inserts in batches (up to 500 messages or 100 ms) with `ON CONFLICT DO NOTHING`, and commits Kafka offsets only after the database transaction commits. A crash or rebalance redelivers at most the uncommitted batch, and the primary key absorbs it.

### Producer: three replicas, each streaming every symbol

- **"The connection will drop at some point."** With three independent WebSocket connections in three AZs, one drop loses nothing, because the other two still deliver every trade, and the primary key drops the copies.
- **Reconnects.** Each producer treats 30 s of silence as a dead socket and reconnects with jittered exponential backoff.
- **Raw messages.** The producer publishes Binance's JSON as received, keyed by symbol, with an idempotent `acks=all` producer. The edge that can't be replayed stays simple; parsing happens in the consumer, which can be fixed and replayed from the topic.

### Completeness: data probe, backfill and watermarks

- **The data probe** measures what actually landed in PostgreSQL, from outside the pipeline, so it also sees what the pipeline can't see about itself.
- **The backfill** is a CronJob, every 5 minutes, for when every connection drops at once:
  - It fetches missing trades from Binance's REST API (`historicalTrades`) and publishes them through the producer's own Kafka code, so the consumer stays the only writer to `trades`.
  - It paces its calls by Binance's `x-mbx-used-weight-1m` header, up to 4,500 of the 6,000 weight allowed per minute, and stops on 429 or 418.
- **Watermarks**, one per symbol in `trade_watermarks`, mean "every trade ID up to here is present":
  - Both the probe and the backfill scan forward from them along the primary key, so no time window decides whether a gap counts.
  - The backfill never moves a watermark past a gap that's still open, so a gap of any length or age stays reported until it's filled.
  - A gap counts only once the trade after it has been in the table for 30 s, about 100× the observed p99, so trades still in flight don't count.

### Scaling: KEDA on consumer lag

- **Why autoscale at all?** Volume varies by an order of magnitude through the day.
- **Why lag and not CPU?** The consumer waits on the database, not the CPU, so the consumer group's lag is the real signal.
- **The range:** 3 to 6 replicas.
  - At least one per AZ.
  - At most one per partition.
  - Target: 500 messages of lag per replica, with a 5-minute window before scaling down.

### Monitoring: CloudWatch

- **Why CloudWatch?** The sandbox doesn't allow Amazon Managed Prometheus or Grafana, and CloudWatch already has the MSK and RDS metrics.
- **How it's wired:**
  - Container logs and Container Insights metrics come from the `amazon-cloudwatch-observability` add-on.
  - The probe publishes the metrics.
  - One composite alarm turns them into a single health state, the one the health command reads, and publishes changes to SNS.

### Identity and secrets

- **IRSA** for every workload, each role trusted by exactly one service account. EKS Pod Identity isn't possible: the permissions boundary doesn't allow `eks-auth:*`.
- **Inline role policies**, because the sandbox restricts creating managed policies.
- **IAM authentication to MSK and RDS**, so there are no Kafka or database passwords anywhere.
- **Endpoints** are published by Terraform to SSM Parameter Store, and External Secrets copies them into a Kubernetes Secret per app, reading with that app's own role.
- **The Flyway master password** exists only in an in-memory volume, for the length of the migration Job.
- **Git** stays clean: a gitleaks pre-commit hook scans every commit, and values files hold no secrets.

### Delivery

- **Self-hosted Argo CD.** The managed EKS capability needs IAM Identity Center. A root Application manages itself, the AppProjects, the platform (External Secrets, KEDA) and the services, in sync waves.
- **The bootstrap.** The EKS API is private and the sandbox doesn't allow SSM, so nothing outside the VPC can reach the cluster:
  - The `argocd` unit launches a one-shot instance in a private subnet, with no inbound rules and no key pair. It installs Argo CD and the root Application, prints the result to its console, and terminates itself.
  - The apply waits for that result.
  - `terragrunt apply -replace=terraform_data.bootstrap` re-runs it.
- **Artifacts:**
  - Images are tagged with the git tree hash of their app directory, so the same code always gets the same immutable tag.
  - Charts are versioned OCI artifacts in ECR, and CI refuses to republish changed content under an existing version.
  - After pushing images, CI commits the new tags to the values files, and Argo CD rolls them out.
- **Argo CD polls Git every minute.** With no inbound access, GitHub can't send a webhook.

### Network and cluster

- **One VPC, three tiers:**
  - private /19s for nodes and pods, since the VPC CNI gives pods subnet IPs;
  - public /24s that hold only the NAT gateway;
  - isolated database /24s for RDS and MSK, with no NAT or internet route.
- **A single NAT gateway,** because the account is shared and Elastic IPs are scarce. Losing its AZ loses egress. The S3 gateway endpoint keeps ECR image layers off the NAT, at no cost.
- **EKS 1.37 with a private API only.**
  - Authentication uses access entries, and Kubernetes secrets are envelope-encrypted with KMS.
  - Nodes are 3× `t3.large`, one per AZ, with a pinned AMI release, so nodes change only through a reviewed commit.
  - IMDSv2 with hop limit 1, so pods can't use the node role.
- **Terraform:** one Terragrunt unit per component, each with its own state, so `run --all` handles ordering. Community modules (`terraform-aws-modules/*`) are pinned and wrapped in `modules/`.

## Assumptions and shortcuts

- **The symbols.** `maticusdt` is dropped. Binance halted it after the MATIC→POL migration. The stream has 9 symbols.
- **State locking** uses S3-native lock files (`use_lockfile`) instead of the provided DynamoDB table, since Terraform deprecated `dynamodb_table`. This requires Terraform ≥ 1.10.
- **No operator access to the cluster.** The API is private and SSM was declined, so everything goes through Git and is observed through CloudWatch.
- **CI after a fresh apply.** It must be re-run after a destroy and fresh apply, because force-deleting ECR removes the images and charts. Only `main` of this repo can assume the push role.
- **GitOps config lives in the app repo, and the CI bot commits image tags to `main`.** In production that would be a separate GitOps repo, updated by pull requests from a GitHub App.
- **One Argo CD per cluster.** To not centralize GitOps failures.
- **Chart pulls from ECR.** External Secrets mints Argo CD's ECR tokens, because self-hosted Argo CD has no native ECR auth.
- **Migrations connect as the RDS master user.** In a real env, a migrator role is the way to go.
- **Completeness after a fresh deploy.** The probe reports missing trades only once the backfill's first run (≤ 5 min) has created the watermarks. Nothing is missed, because each watermark starts at its symbol's first trade.
- **The backfill Job's deadline is 270 s:** the 5-minute schedule minus the pod's 30 s grace period. A longer repair continues from the watermarks in the next run, and the cut-off run shows as `DeadlineExceeded`.
- **Repairs share partitions with live trades.** A very large repair would slow live trades while the consumer works through it.
- **Partitioning by symbol** sends every trade of a symbol to one partition, so BTCUSDT, the busiest symbol, is always handled by a single consumer, and 9 symbols spread unevenly over 6 partitions. Keying by `symbol:trade_id` would spread every symbol across all partitions, while the three producers' copies of a trade, which share that key, would still land on the same partition and consumer.
- **Nobody is subscribed to the SNS topic.** Added this to demonstrate how it may look.

## Repository layout

```
apps/       producer (+ backfill), consumer, data-probe, db-bootstrap: Python, with tests
charts/     one Helm chart per service, plus the database migrations
argocd/     the root Application, AppProjects, Applications and prod values
modules/    Terraform modules, wrapping pinned community modules
live/       Terragrunt units for prod/eu-central-1
```

## Development

Enable the repo's git hooks once per clone (secret scan with gitleaks, `terraform fmt` and `terragrunt hcl fmt` checks):

```sh
git config core.hooksPath .githooks
```
