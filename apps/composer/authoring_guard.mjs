/**
 * composer/authoring_guard.mjs
 */
import crypto from 'node:crypto';
import path from 'node:path';

const BANNED = [/\bshould\b/i, /\bprobably\b/i, /\bmaybe\b/i];
function sha256(s) { return crypto.createHash('sha256').update(s).digest('hex'); }
function countLines(s){
  if (!s) return 0;
  const a = s.split(/\r?\n/);
  return (a.length && a[a.length-1]==='') ? (a.length-1) : a.length;
}
function hasBannedWords(s){ return BANNED.some(rx=>rx.test(s)); }
function checkEvidencePaths(s){ const m=s.match(/artifacts\/[A-Za-z0-9._/-]+/g)||[]; return m.every(p=>p.startsWith('artifacts/')); }
function maybeJsonParse(s){ try{ return JSON.parse(s); }catch{return null;} }

function densityOk(content, ext){
  const lines = content.split(/\r?\n/);
  const total = Math.max(1, lines.length);
  if (total < 10) {            // çok kısa dosyalara tolerans
    return true;
  }
  const filler = lines.filter(l=>/filler/.test(l)).length/total;
  const meaningful = lines.filter(l=>{
    const t=l.trim();
    if(!t) return false;
    if(/^(\#|\/\/|\*|\/\*|\*\/)/.test(t)) return false;
    if(/filler/.test(t)) return false;
    return t.length>=12;
  }).length/total;
  const minByExt = (e)=>(
    e==='.md' ? 0.35 :
    (e==='.mjs'||e==='.js') ? 0.45 :
    (e==='.yml'||e==='.yaml') ? 0.25 :
    (e==='.json'||e==='.jsonl') ? 0.30 : 0.30
  );
  return (filler<=0.25) && (meaningful>=minByExt(ext));
}

function structuralOk(relPath, content){
  const ext = (path.extname(relPath||'') || '').toLowerCase();
  const s = String(content ?? '');
  // .md → en az 3 başlık + evidence izi
  if (ext === '.md'){
    const h = (s.match(/^#{1,3}\s/mg)||[]).length;
    const v = /evidence|verify|artifacts\/reports/i.test(s);
    return (h >= 3) && v;
  }
  // .mjs/.js → en az 1 export/module.exports + JSDoc
  if (ext === '.mjs' || ext === '.js'){
    return (/\bexport\s+(const|function|class)\b/.test(s) || /module\.exports\s*=/.test(s))
           && /\/\*\*[^]*\*\//.test(s);
  }
  // .yml/.yaml → en az 3 key: value
  if (ext === '.yml' || ext === '.yaml'){
    const kv = (s.match(/^[A-Za-z0-9_.-]+:\s?.+/mg)||[]).length;
    return kv >= 3;
  }
  // .json → parse edilir + type/version alanları (evidence opsiyonel)
  if (ext === '.json'){
    try{
      const o = JSON.parse(s);
      // Array ise başarılı, obje ise type/version kontrolü
      if (Array.isArray(o)) return true;
      return !!(o && typeof o==='object' && o.type && o.version);
    }catch{ return false; }
  }
  // .jsonl → tüm DOLU satırlar JSON olmalı
  if (ext === '.jsonl'){
    const lines = s.split(/\r?\n/).filter(Boolean);
    if (lines.length === 0) return false;
    for (const ln of lines){
      try{ JSON.parse(ln); } catch { return false; }
    }
    return true;
  }
  // .txt/.log → en az 3 dolu satır
  if (ext === '.txt' || ext === '.log'){
    const nonEmpty = s.split(/\r?\n/).filter(l=>l.trim()).length;
    return nonEmpty >= 3;
  }
  // .keep → her zaman kabul (placeholder)
  if (ext === '.keep') return true;
  // uzantısız/no-ext → en az 1 dolu satır
  if (!ext){
    return s.trim().length > 0;
  }
  // diğer tüm uzantılar → yapısal kontrol yok, TRUE
  return true;
}

export async function validateContent({ relPath, content, predicted, required }){
  const actual = countLines(content);
  const okLines = actual >= predicted && actual <= required;
  const banned = hasBannedWords(content) ? ['banned_words_found'] : [];
  const evOk = checkEvidencePaths(content);
  const ext = (path.extname(relPath||'') || '').toLowerCase();
  const quality = densityOk(content, ext);
  const struct = !!structuralOk(relPath, content); // her durumda boolean
  
  let jsonOk = true;
  if (relPath.endsWith('.json')){
    const parsed = maybeJsonParse(content);
    if (parsed && typeof parsed === 'object'){
      jsonOk = ('type' in parsed && 'version' in parsed) || !('type' in parsed);
    }
  }
  // JSONL için: sadece parse edilebilir olması yeterli (structural check zaten yapıyor)
  if (relPath.endsWith('.jsonl')){
    jsonOk = true; // JSONL için type/version zorunlu değil
  }
  
  const ok = okLines && evOk && jsonOk && quality && struct && banned.length===0;
  return { 
    ok, 
    relPath, 
    actual_lines: actual, 
    predicted, 
    required, 
    ev_paths_ok: evOk, 
    json_fields_ok: jsonOk,
    quality_ok: quality,
    structural_ok: struct,
    banned_flags: banned, 
    content_hash: sha256(content)
  };
}