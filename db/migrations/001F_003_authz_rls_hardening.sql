-- PSI-CIM-AUTHZ-RLS-001
-- NEW post-001F hardening migration. Not historical lineage.
-- Replaces mutable app.user_id RLS predicates with verified Neon-Auth-derived PSI identity.

BEGIN;

DROP POLICY IF EXISTS goals_user_scope ON goals;
CREATE POLICY goals_user_scope ON goals
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS user_medications_user_scope ON user_medications;
CREATE POLICY user_medications_user_scope ON user_medications
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS stack_user_scope ON user_stack_items;
CREATE POLICY stack_user_scope ON user_stack_items
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS experiments_user_scope ON experiments;
CREATE POLICY experiments_user_scope ON experiments
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS observations_user_scope ON observations;
CREATE POLICY observations_user_scope ON observations
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS recommendations_user_scope ON recommendations;
CREATE POLICY recommendations_user_scope ON recommendations
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

DROP POLICY IF EXISTS decisions_user_scope ON decisions;
CREATE POLICY decisions_user_scope ON decisions
  USING (user_id=psi_current_user_from_auth())
  WITH CHECK (user_id=psi_current_user_from_auth());

COMMIT;
