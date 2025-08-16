/**
 * composer/merge.mjs
 */
export function deepMerge(base, overlay){
  if(Array.isArray(base) && Array.isArray(overlay)){
    const seen=new Set(); const out=[];
    for(const v of [...base, ...overlay]){ const k=JSON.stringify(v); if(!seen.has(k)){ seen.add(k); out.push(v); } }
    return out;
  }
  if(isObject(base) && isObject(overlay)){
    const keys=[...new Set([...Object.keys(base),...Object.keys(overlay)])].sort();
    const out={}; for(const k of keys){ out[k]=deepMerge(base[k], overlay[k]); }
    return out;
  }
  return overlay !== undefined ? overlay : base;
}
function isObject(x){ return x && typeof x==='object' && !Array.isArray(x); }
