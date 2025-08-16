import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs/promises";
import { spawn } from "node:child_process";

async function main() {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);

  const ROOT = path.resolve(__dirname, "..");
  const OUTDIR = path.resolve(process.env.GENESIS_OUTDIR || "build/genesis_out");
  process.env.GENESIS_OUTDIR = OUTDIR;

  await fs.mkdir(OUTDIR, { recursive: true });
  process.chdir(ROOT); // modül çözümlemesi için kökte kal

  const target = path.join(ROOT, "apps", "composer", "compose.ACTUAL.mjs");

  // 1) ESM modülünü import etmeyi dene
  let mod = null;
  try {
    mod = await import(pathToFileURL(target).href);
  } catch (err) {
    // import başarısız olabilir; spawn fallback'ına düşeceğiz
  }

  // 2) Fonksiyonel export varsa çalıştır
  const maybeFn = mod?.default ?? mod?.compose ?? mod?.run;
  if (typeof maybeFn === "function") {
    try {
      await maybeFn({ outDir: OUTDIR });
      console.log("[compose_sandbox] DONE →", OUTDIR);
      return;
    } catch (err) {
      console.error("[compose_sandbox] compose function threw:", err?.stack || err);
      process.exit(3);
    }
  }

  // 3) Fallback: CLI gibi spawn et (ACTUAL kendi işini yapsın)
  await new Promise((resolve, reject) => {
    const p = spawn(
      process.execPath,
      [target, "--outDir", OUTDIR],
      { stdio: "inherit", env: { ...process.env, GENESIS_OUTDIR: OUTDIR } }
    );
    p.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error("compose.ACTUAL exited with code " + code));
    });
    p.on("error", reject);
  });

  console.log("[compose_sandbox] DONE →", OUTDIR);
}

main().catch((e) => {
  console.error("[compose_sandbox] fatal:", e?.stack || e);
  process.exit(2);
});
