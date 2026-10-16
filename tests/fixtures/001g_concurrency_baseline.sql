CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Minimal pre-001G dependency required by the real concurrency harness.
-- This is intentionally not a synthetic copy of 001G runtime logic.
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);
