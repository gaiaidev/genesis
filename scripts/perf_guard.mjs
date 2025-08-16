import { spawn } from "node:child_process";
const url = process.env.PERF_URL || "http://localhost:3002/health";
const runs = Number(process.env.PERF_RUNS||"60");       // toplam istek
const conc = Number(process.env.PERF_CONCURRENCY||"6"); // eşzamanlı
const p95th = Number(process.env.P95_MS||"200");
const spawnServer = process.env.PERF_SPAWN === "1";
const req = async ()=> {
  const t0 = performance.now();
  const r = await fetch(url); if(!r.ok) throw new Error(String(r.status));
  await r.text(); return performance.now()-t0;
};
const sleep = (ms)=> new Promise(r=>setTimeout(r,ms));
let srv; async function waitHealth(max=15){ for(let i=0;i<max;i++){ try{ const r=await fetch(url); if(r.ok) return true; }catch{} await sleep(500) } return false }
async function run(){
  if(spawnServer){
    srv = spawn("node", ["apps/api/src/index.mjs"], { stdio:"inherit" });
    process.on("exit", ()=>{ try{ srv.kill() }catch{} });
    const ok = await waitHealth(); if(!ok){ console.error("health not ready"); process.exit(2) }
  }
  const lat=[]; let i=0;
  const worker = async()=>{ while(true){ const id=i++; if(id>=runs) break; const d=await req().catch(()=>Infinity); lat.push(d) } };
  await Promise.all(Array.from({length: conc}, worker));
  const good = lat.filter(x=>isFinite(x)); if(good.length===0){ console.error("no successful samples"); process.exit(2) }
  good.sort((a,b)=>a-b); const idx=Math.ceil(good.length*0.95)-1; const p95=good[Math.max(0,idx)];
  console.log(JSON.stringify({samples:good.length, p95_ms:Number(p95.toFixed(2))}));
  if(p95>p95th){ console.error("PERF FAIL: p95="+p95.toFixed(2)+"ms > "+p95th+"ms"); process.exit(3) }
}
run().finally(()=>{ if(srv){ try{ srv.kill() }catch{} } });
