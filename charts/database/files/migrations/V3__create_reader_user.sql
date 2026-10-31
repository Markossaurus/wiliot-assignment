-- The data probe's user: reads the table to measure freshness and completeness, nothing else.
CREATE ROLE ${readerUser} LOGIN;
GRANT rds_iam TO ${readerUser};
GRANT SELECT ON trades TO ${readerUser};
