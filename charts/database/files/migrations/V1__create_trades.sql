CREATE TABLE trades (
    symbol      text        NOT NULL,
    trade_id    bigint      NOT NULL,
    price       numeric     NOT NULL,
    quantity    numeric     NOT NULL,
    -- Derived by the database, so it always equals price * quantity exactly.
    notional    numeric     GENERATED ALWAYS AS (price * quantity) STORED,
    trade_time  timestamptz NOT NULL,
    ingested_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (symbol, trade_id)
);

-- Freshness checks filter on recently ingested rows.
CREATE INDEX trades_ingested_at_idx ON trades (ingested_at);
