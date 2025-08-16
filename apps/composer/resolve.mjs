/**
 * composer/resolve.mjs
 */
import crypto from 'node:crypto';
function sha256(buf){ return crypto.createHash('sha256').update(buf).digest('hex'); }
export function resolveConflicts(items){
  const sorted=[...items].sort((a,b)=>(`${a.packageId}\u0000${a.file}`).localeCompare(`${b.packageId}\u0000${b.file}`));
  const map=new Map(); const explain=[];
  for(const it of sorted){ const key=it.file; if(map.has(key)) explain.push({ file:key, replaced_by: it.packageId }); map.set(key,it); }
  const out=[...map.values()]; const report={ ts:new Date('2025-01-01T00:00:00Z').toISOString(), total: out.length, explain };
  report.hash=sha256(Buffer.from(JSON.stringify(out))); return { files: out, report };
}
