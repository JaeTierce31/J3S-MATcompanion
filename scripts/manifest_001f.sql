-- PSI-CIM-001F deterministic runtime object manifest.
-- Read-only. Emits SHA-256 fingerprints for public relations/functions/triggers/policies.
-- Requires pgcrypto, which is part of the recovered PSI baseline.

WITH rels AS (
  SELECT c.oid,n.nspname,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,
         CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) ELSE '' END AS viewdef,
         coalesce((SELECT string_agg(format('%s:%s:%s:%s:%s',a.attnum,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,coalesce(pg_get_expr(ad.adbin,ad.adrelid),'')),'|' ORDER BY a.attnum)
                   FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
                   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'') AS cols,
         coalesce((SELECT string_agg(pg_get_constraintdef(con.oid,true),'|' ORDER BY con.conname)
                   FROM pg_constraint con WHERE con.conrelid=c.oid),'') AS cons,
         coalesce((SELECT string_agg(pg_get_indexdef(i.indexrelid),'|' ORDER BY ci.relname)
                   FROM pg_index i JOIN pg_class ci ON ci.oid=i.indexrelid WHERE i.indrelid=c.oid),'') AS idxs
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','v')
), relation_manifest AS (
  SELECT 'relation'::text AS object_class,
         relname AS object_name,
         CASE relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' END AS object_type,
         encode(digest(cols||E'\n'||cons||E'\n'||idxs||E'\n'||viewdef,'sha256'),'hex') AS definition_sha256,
         jsonb_build_object('rls',relrowsecurity,'force_rls',relforcerowsecurity) AS metadata
  FROM rels
), function_manifest AS (
  SELECT 'function'::text AS object_class,
         p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS object_name,
         'function'::text AS object_type,
         encode(digest(pg_get_functiondef(p.oid),'sha256'),'hex') AS definition_sha256,
         jsonb_build_object('security_definer',p.prosecdef,'owner',pg_get_userbyid(p.proowner),'config',p.proconfig) AS metadata
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
), trigger_manifest AS (
  SELECT 'trigger'::text AS object_class,
         c.relname||'.'||t.tgname AS object_name,
         'trigger'::text AS object_type,
         encode(digest(pg_get_triggerdef(t.oid,true),'sha256'),'hex') AS definition_sha256,
         '{}'::jsonb AS metadata
  FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND NOT t.tgisinternal
), policy_manifest AS (
  SELECT 'policy'::text AS object_class,
         tablename||'.'||policyname AS object_name,
         'rls_policy'::text AS object_type,
         encode(digest(coalesce(qual,'')||E'\n'||coalesce(with_check,''),'sha256'),'hex') AS definition_sha256,
         jsonb_build_object('permissive',permissive,'roles',roles,'cmd',cmd) AS metadata
  FROM pg_policies WHERE schemaname='public'
), all_objects AS (
  SELECT * FROM relation_manifest
  UNION ALL SELECT * FROM function_manifest
  UNION ALL SELECT * FROM trigger_manifest
  UNION ALL SELECT * FROM policy_manifest
)
SELECT jsonb_pretty(jsonb_build_object(
  'generated_at',clock_timestamp(),
  'database',current_database(),
  'server_version',current_setting('server_version'),
  'counts',jsonb_build_object(
    'relations',(SELECT count(*) FROM relation_manifest),
    'functions',(SELECT count(*) FROM function_manifest),
    'triggers',(SELECT count(*) FROM trigger_manifest),
    'policies',(SELECT count(*) FROM policy_manifest)
  ),
  'objects',(SELECT jsonb_agg(jsonb_build_object(
      'class',object_class,'name',object_name,'type',object_type,
      'sha256',definition_sha256,'metadata',metadata
    ) ORDER BY object_class,object_name) FROM all_objects)
));
