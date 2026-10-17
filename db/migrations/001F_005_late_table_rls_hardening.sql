-- PSI-CIM-001F-HARDEN-005
-- NEW post-001F defense-in-depth hardening; NOT original signed historical lineage.
-- Purpose: protect later user-owned 001D/001E tables if direct grants are ever widened.
-- Policy posture is intentionally SELECT-only. Canonical writes remain governed/owner paths.
-- user_auth_identities is RLS-enabled with NO client policy (direct deny-all).

BEGIN;

-- Direct user-keyed projections / objects.
ALTER TABLE observation_daily_rollups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS observation_daily_rollups_user_read ON observation_daily_rollups;
CREATE POLICY observation_daily_rollups_user_read ON observation_daily_rollups
  FOR SELECT USING (user_id = psi_current_user_from_auth());

ALTER TABLE observation_weekly_rollups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS observation_weekly_rollups_user_read ON observation_weekly_rollups;
CREATE POLICY observation_weekly_rollups_user_read ON observation_weekly_rollups
  FOR SELECT USING (user_id = psi_current_user_from_auth());

ALTER TABLE personal_insights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS personal_insights_user_read ON personal_insights;
CREATE POLICY personal_insights_user_read ON personal_insights
  FOR SELECT USING (user_id = psi_current_user_from_auth());

ALTER TABLE attention_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS attention_items_user_read ON attention_items;
CREATE POLICY attention_items_user_read ON attention_items
  FOR SELECT USING (user_id = psi_current_user_from_auth());

-- Experiment-owned child tables inherit scope from the experiment owner.
ALTER TABLE experiment_protocols ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS experiment_protocols_user_read ON experiment_protocols;
CREATE POLICY experiment_protocols_user_read ON experiment_protocols
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM experiments e
      WHERE e.id = experiment_protocols.experiment_id
        AND e.user_id = psi_current_user_from_auth()
    )
  );

ALTER TABLE experiment_checkins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS experiment_checkins_user_read ON experiment_checkins;
CREATE POLICY experiment_checkins_user_read ON experiment_checkins
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM experiments e
      WHERE e.id = experiment_checkins.experiment_id
        AND e.user_id = psi_current_user_from_auth()
    )
  );

-- Insight-owned child tables inherit scope from the insight owner.
ALTER TABLE insight_confidence_components ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS insight_confidence_components_user_read ON insight_confidence_components;
CREATE POLICY insight_confidence_components_user_read ON insight_confidence_components
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM personal_insights pi
      WHERE pi.id = insight_confidence_components.insight_id
        AND pi.user_id = psi_current_user_from_auth()
    )
  );

ALTER TABLE insight_evidence_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS insight_evidence_links_user_read ON insight_evidence_links;
CREATE POLICY insight_evidence_links_user_read ON insight_evidence_links
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM personal_insights pi
      WHERE pi.id = insight_evidence_links.insight_id
        AND pi.user_id = psi_current_user_from_auth()
    )
  );

-- Identity mapping is security-sensitive. RLS with no permissive client policy
-- means non-owner direct access is denied even if a table grant appears later.
ALTER TABLE user_auth_identities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_auth_identities_user_read ON user_auth_identities;
DROP POLICY IF EXISTS user_auth_identities_user_scope ON user_auth_identities;

COMMIT;
