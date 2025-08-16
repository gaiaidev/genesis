#!/usr/bin/env node
/**
 * Genesis Validate (composer edition)
 * - 1) Health check: /health (expects ok:true + fields)
 * - 2) File sanity: required files exist
 * - 3) Constitution fingerprint: stable hash logged
 * - 4) Certificate emit: docs/certificate.json (score=1.00 if all pass)
 */
import { readFileSync, existsSync, writeFileSync } from "fs";
import { createHash } from "crypto";
import { spawnSync } from "child_process";
import path from "path";

const ROOT = process.cwd();
const requiredFiles = [
  "apps/api/src/index.mjs",
  "apps/api/src/routes/health.mjs",
  "docs/API_SPEC.md"
];

function fail(msg) { console.error("✖", msg); process.exit(1); }
function ok(msg)   { console.log("✔", msg); }

for (const f of requiredFiles) {
  if (!existsSync(path.join(ROOT, f))) fail(`missing required file: ${f}`);
}
ok("Required files present");

let score = 0;
let passed = 0;

/* 1) Health check via local test runner if present, otherwise curl */
function healthCheck() {
  const runner = path.join(ROOT, "genesis-test-runner.mjs");
  if (existsSync(runner)) {
    const p = spawnSync("node", [runner], { encoding: "utf8" });
    if (p.status !== 0) fail("health check failed via test runner");
    ok("Health check passed (runner)");
    return true;
  }
  const p = spawnSync("bash", ["-lc", "curl -fsS http://localhost:3001/health"], { encoding: "utf8" });
  if (p.status !== 0) fail("health check failed via curl");
  const j = JSON.parse(p.stdout);
  if (j.ok !== true || !j.version || !j.uptimeSec || !j.now) fail("health payload invalid");
  ok("Health check passed (curl)");
  return true;
}
if (healthCheck()) { passed++; }

/* 2) API spec presence */
const spec = readFileSync(path.join(ROOT, "docs/API_SPEC.md"), "utf8");
if (!/GET\s+\/health/.test(spec)) fail("API_SPEC.md missing /health doc");
ok("API spec sanity OK"); passed++;

/* 3) Constitution fingerprint (optional) */
let constitutionPath = path.join(ROOT, "constitution/final_constitution.jsonl");
let fingerprint = "absent";
if (existsSync(constitutionPath)) {
  const buf = readFileSync(constitutionPath);
  fingerprint = createHash("sha256").update(buf).digest("hex").slice(0,16);
  ok("Constitution fingerprint " + fingerprint);
  passed++;
} else {
  ok("Constitution not found (skipping)"); 
}

/* 4) Composer sanity (compose.mjs/authoring_guard.mjs exist?) */
const composerOK = ["compose.mjs","authoring_guard.mjs"].every(f=>existsSync(path.join(ROOT,"apps/composer",f)));
if (composerOK) { ok("Composer files present"); passed++; }
else { fail("Composer files missing (compose.mjs/authoring_guard.mjs)"); }

/* 5) Evidence checks from evidence_plan.jsonl */
function readJSONSafe(p) {
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; }
}
function contains(txt, needle){ return (txt||"").includes(needle); }
function get(obj, pathStr) {
  if (!obj || typeof obj !== "object") return undefined;
  return pathStr.split('.').reduce((o,k)=> (o && o[k]!=null) ? o[k] : undefined, obj);
}

const EPLAN = path.join(ROOT, "constitution/evidence_plan.jsonl");
let evidenceChecks = 0;
let evidencePassed = 0;

if (existsSync(EPLAN)) {
  const lines = readFileSync(EPLAN, "utf8")
    .split(/\r?\n/).filter(l=>l && !l.trim().startsWith("#"));
  
  for (const line of lines) {
    try {
      const row = JSON.parse(line);
      const art = path.join(ROOT, row.artifact);
      evidenceChecks++;
      
      if (!existsSync(art)) {
        console.log(`  ⚠ Evidence missing: ${row.id} → ${row.artifact}`);
        continue;
      }

      const check = row.check || "exists";
      let okCheck = false;

      if (check === "exists") {
        okCheck = true;
      } else if (check.startsWith("contains('")) {
        const needle = check.match(/contains\('(.+)'\)/)?.[1] || "";
        const txt = readFileSync(art, "utf8");
        okCheck = contains(txt, needle);
      } else if (check.startsWith("startsWith('")) {
        const needle = check.match(/startsWith\('(.+)'\)/)?.[1] || "";
        const txt = readFileSync(art, "utf8");
        okCheck = txt.startsWith(needle);
      } else if (check === "json.has(traceId)") {
        const obj = readJSONSafe(art);
        okCheck = obj && !!obj.traceId;
      } else if (check === "json.isStructured==true") {
        const obj = readJSONSafe(art);
        okCheck = obj && obj.json?.isStructured === true;
      } else if (check.startsWith("hasKeys(")) {
        const keysStr = check.match(/hasKeys\(\[(.+)\]\)/)?.[1] || "";
        const keys = keysStr.split(',').map(k => k.trim().replace(/['"]/g, ''));
        const obj = readJSONSafe(art);
        okCheck = obj && keys.every(k => k in obj);
      } else if (check.includes("==")) {
        // Handle all equality checks (string, boolean, nested)
        const parts = check.split("==");
        if (parts.length === 2) {
          const field = parts[0].trim();
          const expected = parts[1].trim().replace(/['"]/g, '');
          const obj = readJSONSafe(art);
          
          if (obj) {
            // Check for nested field
            if (field.includes('.')) {
              const val = get(obj, field);
              okCheck = String(val) === expected;
            } else {
              // Direct field
              const val = obj[field];
              if (expected === 'true') okCheck = val === true;
              else if (expected === 'false') okCheck = val === false;
              else if (expected === 'PASS') okCheck = val === 'PASS';
              else if (!isNaN(Number(expected))) okCheck = Number(val) === Number(expected);
              else okCheck = String(val) === expected;
            }
          }
        }
      } else if (check.includes(">=") || check.includes("<=")) {
        // Handle numeric comparisons
        const m = check.match(/^(.+?)(>=|<=)(.+)$/);
        if (m) {
          const field = m[1].trim();
          const op = m[2];
          const expected = Number(m[3]);
          const obj = readJSONSafe(art);
          
          if (obj) {
            let val;
            if (field.includes('.')) {
              val = Number(get(obj, field));
            } else {
              val = Number(obj[field]);
            }
            
            if (!isNaN(val) && !isNaN(expected)) {
              if (op === ">=") okCheck = val >= expected;
              else if (op === "<=") okCheck = val <= expected;
            }
          }
        }
      }

      if (okCheck) {
        evidencePassed++;
      } else {
        console.log(`  ⚠ Evidence check failed: ${row.id} (${row.check})`);
      }
    } catch (e) {
      console.log(`  ⚠ Evidence parse error: ${e.message}`);
    }
  }
  
  ok(`Evidence checks: ${evidencePassed}/${evidenceChecks} passed`);
  if (evidencePassed === evidenceChecks) passed++;
} else {
  ok("Evidence plan not found (skipping)");
}

/* Score calc: now includes evidence checks */
const totalChecks = existsSync(EPLAN) ? 5 : 4;
score = (passed >= totalChecks) ? 1.00 : (passed/totalChecks);

const certificate = {
  framework: "Genesis",
  service: "genesis-api",
  score,
  passed,
  totalChecks,
  checks: ["health","api_spec","constitution_fingerprint","composer_presence","evidence_validation"],
  evidenceChecks: {
    total: evidenceChecks,
    passed: evidencePassed
  },
  fingerprint,
  at: new Date().toISOString()
};
const out = path.join(ROOT, "docs/certificate.json");
writeFileSync(out, JSON.stringify(certificate, null, 2));
ok(`Certificate written: docs/certificate.json (score=${score.toFixed(2)})`);

if (score < 1.0) process.exit(1);

// PROVENANCE ADDITION (Enterprise hardening)
import crypto from "crypto";
function getHash(content) {
  return crypto.createHash("sha256").update(content).digest("hex").slice(0, 16);
}
try {
  const targetsContent = fs.readFileSync("constitution/targets/lines.jsonl", "utf8");
  const certificate = JSON.parse(fs.readFileSync("docs/certificate.json", "utf8"));
  certificate.provenance = {
    targetsHash: getHash(targetsContent),
    timestamp: new Date().toISOString()
  };
  fs.writeFileSync("docs/certificate.json", JSON.stringify(certificate, null, 2));
} catch (e) {
  // Silent fail for backward compat
}
