-- PSI-CIM hardened post-001F manifest root.
-- This is intentionally distinct from canonical_manifest_root_001f.sql:
-- the latter fingerprints the verified historical product baseline; this one
-- additionally fingerprints the post-lineage authorization/security posture.
-- Portable across PostgreSQL 17 role OIDs by normalizing grantees to names.

WITH rels AS (
  SELECT c.oid,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,
         CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) ELSE '' END AS viewdef,
         coalesce((SELECT string_agg(format('%s:%s:%s:%s:%s',a.attnum,a.attname,
                    format_type(a.atttypid,a.atttypmod),a.attnotnull,
                    coalesce(pg_get_expr(ad.adbin,ad.adrelid),'')),'|' ORDER BY a.attnum)
                   FROM pg_attribute a
                   LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
                   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'') cols,
         coalesce((SELECT string_agg(pg_get_constraintdef(con.oid,true),'|' ORDER BY con.conname)
                   FROM pg_constraint con WHERE con.conrelid=c.oid),'') cons,
         coalesce((SELECT string_agg(pg_get_indexdef(i.indexrelid),'|' ORDER BY ci.relname)
                   FROM pg_index i JOIN pg_class ci ON ci.oid=i.indexrelid
                   WHERE i.indrelid=c.oid),'') idxs
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','v')
    AND c.relname NOT IN ('psi_perf_results','psi_performance_results','psi_verification_results')
), funcs AS (
  SELECT p.oid,p.proname,pg_get_function_identity_arguments(p.oid) AS args,
         p.prosecdef,p.proconfig,p.proacl,p.proowner
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname<>'psi_record_test'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
    )
), objects AS (
  SELECT 'relation'::text AS cls,relname AS name,
         encode(digest(cols||E'\n'||cons||E'\n'||idxs||E'\n'||viewdef,'sha256'),'hex')
           ||':'||relrowsecurity::text||':'||relforcerowsecurity::text AS val
  FROM rels
  UNION ALL
  SELECT 'function',proname||'('||args||')',
         encode(digest(pg_get_functiondef(oid),'sha256'),'hex')
           ||':definer='||prosecdef::text
           ||':config='||coalesce(array_to_string(proconfig,','),'')
  FROM funcs
  UNION ALL
  SELECT 'trigger',c.relname||'.'||t.tgname,
         encode(digest(pg_get_triggerdef(t.oid,true),'sha256'),'hex')
  FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND NOT t.tgisinternal
  UNION ALL
  SELECT 'policy',tablename||'.'||policyname,
         encode(digest(coalesce(qual,'')||E'\n'||coalesce(with_check,''),'sha256'),'hex')
           ||':'||permissive||':'||cmd||':'||roles::text
  FROM pg_policies WHERE schemaname='public'
  UNION ALL
  SELECT 'relation_acl',r.relname||'|'||CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
         a.privilege_type||':'||a.is_grantable::text
  FROM rels r
  JOIN pg_class c ON c.oid=r.oid
  CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 's' ELSE 'r' END,c.relowner))) a
  WHERE a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('psi_dashboard_reader','authenticated')
  UNION ALL
  SELECT 'function_acl',f.proname||'('||f.args||')|'||CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
         a.privilege_type||':'||a.is_grantable::text
  FROM funcs f
  CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl,acldefault('f',f.proowner))) a
  WHERE a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('psi_dashboard_reader','authenticated')
  UNION ALL
  SELECT 'schema_acl',n.nspname||'|'||CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
         a.privilege_type||':'||a.is_grantable::text
  FROM pg_namespace n
  CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl,acldefault('n',n.nspowner))) a
  WHERE n.nspname IN ('public','auth')
    AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('psi_dashboard_reader','authenticated'))
), normalized AS (
  SELECT cls||'|'||name||'|'||val AS line FROM objects
)
SELECT count(*)::text||'|'||
       encode(digest(string_agg(line,E'\n' ORDER BY line),'sha256'),'hex')
FROM normalized;
