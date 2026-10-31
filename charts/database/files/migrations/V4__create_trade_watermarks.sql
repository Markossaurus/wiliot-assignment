-- Per symbol, every trade ID up to verified_through_id is in trades. Only the backfill moves it,
-- never past a missing ID, so a gap stays reported until it is filled, however long or old it is.
CREATE TABLE trade_watermarks (
    symbol              text        PRIMARY KEY,
    verified_through_id bigint      NOT NULL,
    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- The backfill's user: finds gaps in trades and keeps the watermarks. It can't write trades; what it
-- repairs goes through Kafka and the consumer like every other trade.
CREATE ROLE ${backfillUser} LOGIN;
GRANT rds_iam TO ${backfillUser};
GRANT SELECT ON trades TO ${backfillUser};
GRANT SELECT, INSERT, UPDATE ON trade_watermarks TO ${backfillUser};

-- The data probe counts missing trades from the watermarks onward.
GRANT SELECT ON trade_watermarks TO ${readerUser};
