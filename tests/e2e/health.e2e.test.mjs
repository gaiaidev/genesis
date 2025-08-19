import { beforeAll, afterAll, it, expect } from "vitest";
import { spawn } from "node:child_process";

let proc;
const URL = "http://127.0.0.1:3002/health";
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function waitHealthy(t = 10000) {
  const s = Date.now();
  while (Date.now() - s < t) {
    try {
      const r = await fetch(URL);
      if (r.ok) return true;
    } catch {
      // ignore
    }
    await sleep(200);
  }
  return false;
}

beforeAll(async () => {
  proc = spawn(process.execPath, ["apps/api/src/index.mjs"], { stdio: "ignore" });
  if (!(await waitHealthy())) throw new Error("API not healthy in time");
}, 20_000);

afterAll(() => {
  try {
    proc?.kill();
  } catch {
    // ignore
  }
});

it("GET /health → {ok:true, ts:number}", async () => {
  const r = await fetch(URL);
  expect(r.ok).toBe(true);
  const j = await r.json();
  expect(j.ok).toBe(true);
  expect(typeof j.ts).toBe("number");
});