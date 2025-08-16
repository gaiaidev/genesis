/**
 * composer/ci_authoring_guard.mjs
 */
import fs from 'node:fs/promises';
import fss from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { validateContent } from './authoring_guard.mjs';

const args = new Set(process.argv.slice(2));

async function walk(dir){ const out=[]; for(const e of await fs.readdir(dir,{withFileTypes:true})){ const p=path.join(dir,e.name); if(e.isDirectory()) out.push(...await walk(p)); else out.push(p);} return out }

const ZERO=new Set(['logs/run.jsonl','ledger/full_log_master.json','artifacts/checkpoints/latest.json']);

// targets.json'dan pred/req değerlerini yükle
async function loadTargets() {
  const targetMap = new Map();
  try {
    const data = JSON.parse(await fs.readFile('targets.json', 'utf8'));
    for (const t of data) {
      targetMap.set(t.file, { 
        predicted: t.predicted_lines_by_constitution || t.predicted_lines || t.predicted || 0,
        required: t.required_lines_for_perfection || t.required_lines || t.required || t.predicted || 0
      });
    }
  } catch {
    // targets.json yoksa boş Map döner
  }
  return targetMap;
}

(async()=>{
  const targetMap = await loadTargets();
  const files=await walk('.'); 
  let fail=0, ok=0;
  const details=[];
  const seen = new Map(); // hash -> [paths]
  
  for(const f of files){ 
    const rel=f.replace(/^\.\//,''); 
    if(ZERO.has(rel)) continue;
    const content=await fs.readFile(f,'utf8').catch(()=>'');
    const lines=content?content.split(/\n/).length:0;
    
    // targets.json'dan değerleri al, yoksa fallback
    const target = targetMap.get(rel);
    const ext = path.extname(rel).toLowerCase();
    const minimums = {
      '.md': 8, '.json': 10, '.jsonl': 1, 
      '.yml': 6, '.yaml': 6, '.mjs': 6, 
      '.js': 5, '.txt': 3, '.keep': 1
    };
    const min = minimums[ext] || 3;
    
    const predicted = target ? Math.max(target.predicted, min) : Math.max(1, lines-2);
    const required = target ? Math.max(target.required, predicted) : Math.max(lines, 1);
    
    const rep=await validateContent({ relPath:rel, content, predicted, required });
    if(!rep.ok){ fail++; console.error('GUARD FAIL:', rel, rep) } else ok++;
    details.push({ file: rel, ok: rep.ok, guard: rep });
    
    if (content) {
      const h = crypto.createHash('sha256').update(content).digest('hex');
      if (!seen.has(h)) seen.set(h, []);
      seen.get(h).push(rel);
    }
  }
  
  for (const [h, arr] of seen.entries()) {
    if (arr.length > 1) {
      fail++; 
      console.error('DUPLICATE CONTENT FAIL:', arr);
    }
  }
  
  if (args.has('--report')) {
    await fs.mkdir('artifacts/reports', {recursive:true});
    await fs.writeFile('artifacts/reports/ci_fail_report.json', JSON.stringify(details, null, 2));
    
    // CSV export
    const header='file,ok,quality_ok,structural_ok,json_fields_ok,actual_lines,predicted,required\n';
    const rows=details.map(d=>[
      JSON.stringify(d.file),
      d.ok,
      d.guard.quality_ok ?? '',
      d.guard.structural_ok ?? '',
      d.guard.json_fields_ok ?? '',
      d.guard.actual_lines,
      d.guard.predicted,
      d.guard.required
    ].join(',')).join('\n');
    fss.writeFileSync('artifacts/reports/ci_fail_report.csv', header+rows);
    
    console.log(`[REPORT] Written to artifacts/reports/ci_fail_report.json (${details.length} files)`);
    console.log(`[REPORT] Summary: OK=${ok}, FAIL=${fail}`);
  }
  
  if (fail) process.exit(1);
  else process.exit(0);
})().catch(e=>{ console.error(e); process.exit(1) });