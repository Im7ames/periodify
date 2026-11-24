CREATE TABLE IF NOT EXISTS account_state (
  account_hash TEXT PRIMARY KEY,
  revision TEXT NOT NULL,
  ciphertext BLOB NOT NULL
) STRICT;
