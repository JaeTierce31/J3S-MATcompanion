-- Read-only object fingerprints for relation/function drift diagnosis.
WITH rels AS (
  SELECT c.oid,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,
         CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) ELSE '' END AS viewdef,
         coalesce((SELECT string_agg(format('%s:%s:%s:%s:%s',a.attnum,a.attname,
                    format_type(a.atttypid,a.atttypmod),a.attnotnull,
                    coalesce(pg_get_expr(ad.adbin,ad.adrelid),'')),'|' ORDER BY a.attnum)
                   FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
                   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'') cols,
         coalesce((SELECT string_agg(pg_get_constraintdef(con.oid,true),'|' ORDER BY con.conname)
                   FROM pg_constraint con WHERE con.conrelid=c.oid),'') cons,
         coalesce((SELECT string_agg(pg_get_indexdef(i.indexrelid),'|' ORDER BY ci.relname)
                   FROM pg_index i JOIN pg_class ci ON ci.oid=i.indexrelid WHERE i.indrelid=c.oid),'') idxs
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','v')
    AND c.relname NOT IN ('psi_perf_results','psi_performance_results','psi_verification_results')
)
SELECT 'relation|'||relname||'|'||
       encode(digest(cols||E'\n'||cons||E'\n'||idxs||E'\n'||viewdef,'sha256'),'hex')
       ||':'||relrowsecurity::text||':'||relforcerowsecurity::text
FROM rels
UNION ALL
SELECT 'function|'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|'||
       encode(digest(pg_get_functiondef(p.oid),'sha256'),'hex')
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname<>'psi_record_test'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
ORDER BY 1;
