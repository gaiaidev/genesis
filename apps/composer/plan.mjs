import fs from "node:fs";
import path from "node:path";

const CWD = process.cwd();
const cfgPath = path.join(CWD, "project_config.json");
if (!fs.existsSync(cfgPath)) {
  console.error("[plan] project_config.json missing.");
  process.exit(2);
}
const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));

/** Basit profil→modül haritası (gerekirse genişlet) */
const PROFILES = {
  web_saas: [
    "apps/web", "packages/ui", "packages/i18n", "packages/feature-flags",
    "packages/notifications", "apps/web/tests"
  ],
  backend_api: [
    "apps/api", "packages/core", "packages/auth", "packages/payments",
    "packages/ops-sre", "apps/api/tests"
  ],
  backend_realtime: [
    "apps/realtime", "packages/caching", "packages/backend"
  ],
  web_storefront: [
    "apps/storefront", "packages/ui", "packages/payments", "apps/storefront/tests"
  ]
};

/** Ölçek → yaklaşık hedef yoğunluğu (dosya/bileşen katsayıları) */
const SCALE = {
  small:       { baseFiles: 60,  perModule: 6 },
  medium:      { baseFiles: 140, perModule: 12 },
  large:       { baseFiles: 320, perModule: 20 },
  enterprise:  { baseFiles: 640, perModule: 28 }
};

function uniq(arr){ return [...new Set(arr)] }

const selectedProfiles = cfg.profile || [];
let modules = [];
for (const p of selectedProfiles) {
  modules = modules.concat(PROFILES[p] || []);
}
modules = uniq(modules);

/** Feature'lara göre modül eklemeleri */
const f = cfg.features || {};
if (f.realtime) modules.push("apps/realtime");
if (f.admin_panel) modules.push("apps/admin");
if (f.i18n) modules.push("packages/i18n");
if (Array.isArray(f.payments) && f.payments.length) modules.push("packages/payments");
if (Array.isArray(f.auth) && f.auth.length) modules.push("packages/auth");

modules = uniq(modules);

/** Ölçek katsayıları */
const s = SCALE[cfg.scale] || SCALE.medium;
const approxFiles = s.baseFiles + s.perModule * modules.length;

/** İşlevsel kabul kriterleri (line-padding yerine) */
const acceptance = [
  { id: "api.health.200", for: "apps/api", type: "e2e", mustPass: true },
  { id: "auth.flow.basic", for: "packages/auth", type: "unit", mustPass: true },
  { id: "ui.lint.strict", for: "packages/ui", type: "lint", mustPass: true },
  { id: "types.ok", for: "*", type: "typecheck", mustPass: true },
  { id: "perf.p95", for: "apps/api", type: "perf", thresholdMs: (cfg.quality?.p95_ms ?? 200) }
];

/** Hedef dosya planı: dosya listesi vermek yerine "üretilmesi gereken parçalar"
 * ve doğrulama kuralları yazıyoruz. Composer, bunlardan gerçek dosyayı çıkarsın.
 */
const targetsAuto = {
  mode: "dynamic",
  project: cfg.name,
  scale: cfg.scale,
  profiles: selectedProfiles,
  modules,
  approximate_files: approxFiles,
  generation_rules: {
    prefer_tests: !!cfg.quality?.require_tests,
    require_lint_typecheck: !!cfg.quality?.lint_typecheck,
    disallow_padding: true,
    enforce_real_endpoints: true
  },
  acceptance_criteria: acceptance
};

const out = path.join(CWD, "targets.auto.json");
fs.writeFileSync(out, JSON.stringify(targetsAuto, null, 2));
console.log("[plan] targets.auto.json generated:", out);
