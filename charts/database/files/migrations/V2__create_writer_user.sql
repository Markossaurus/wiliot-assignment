-- The consumer's user. Members of rds_iam can only log in with an IAM token, never a password.
CREATE ROLE ${writerUser} LOGIN;
GRANT rds_iam TO ${writerUser};

-- SELECT is needed for INSERT ... RETURNING.
GRANT SELECT, INSERT ON trades TO ${writerUser};
