-- PSI-CIM clean-build compatibility prelude.
-- This file is NEW lineage repair, not part of the historical signed 001B artifact.
-- It exists solely because signed 001B_base.sql grants to psi_dashboard_reader
-- before signed 001C_runtime_hardening.sql historically creates that role.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='psi_dashboard_reader') THEN
    CREATE ROLE psi_dashboard_reader NOLOGIN;
  END IF;
END $$;
