import { spawn } from "node:child_process";

const PERF_TARGET = process.env.PERF_URL || process.env.PERF_TARGET || "http://localhost:3002/health";
const PERF_P95_MS = parseInt(process.env.P95_MS || "200", 10);
const PERF_RUNS = parseInt(process.env.PERF_RUNS || "50", 10);
const PERF_SPAWN = process.env.PERF_SPAWN !== "0"; // "0" ise spawn etme

async function measureP95() {
  let server = null;
  
  if (PERF_SPAWN) {
    // API'yi başlat (CI'de zaten çalışıyor olacak)
    server = spawn("node", ["apps/api/src/index.mjs"], { stdio: "ignore" });
    await new Promise(r => setTimeout(r, 1500)); // API başlaması için bekle
  }

  const times = [];
  for (let i = 0; i < PERF_RUNS; i++) {
    const start = Date.now();
    try {
      await fetch(PERF_TARGET);
      times.push(Date.now() - start);
    } catch (e) {
      if (server) server.kill();
      console.error("Perf test failed:", e.message);
      process.exit(1);
    }
  }

  if (server) server.kill();

  times.sort((a, b) => a - b);
  const p95 = times[Math.floor(times.length * 0.95)];
  console.log(JSON.stringify({ samples: times.length, p95_ms: p95 }));
  
  if (p95 > PERF_P95_MS) {
    console.error("❌ P95 (" + p95 + "ms) > limit (" + PERF_P95_MS + "ms)");
    process.exit(1);
  }
}

measureP95().catch(e => {
  console.error("Fatal:", e);
  process.exit(1);
});
