import { execSync } from "node:child_process";
import fs from "node:fs";

const policy = fs.readFileSync(".policy_no_autofix_paths", "utf8")
  .split(/\r?\n/).map(s => s.trim()).filter(Boolean);

function changedFiles() {
  try {
    // Son 1 commit veya PR diff'i – basit yaklaşım
    return execSync("git diff --name-only HEAD~1..HEAD", { encoding: "utf8" })
      .split(/\r?\n/).filter(Boolean);
  } catch {
    return [];
  }
}

function needsApproval(files) {
  const toRegex = (glob) =>
    new RegExp("^" + glob.replace(/\./g, "\\.").replace(/\*\*/g, ".*").replace(/\*/g, "[^/]*") + "$");
  const regs = policy.map(toRegex);
  return files.some(f => regs.some(r => r.test(f)));
}

function lastCommitMessage() {
  return execSync("git log -1 --pretty=%B", { encoding: "utf8" });
}

const files = changedFiles();
if (needsApproval(files)) {
  const msg = lastCommitMessage();
  if (!/^Approved-By:\s+.+/mi.test(msg)) {
    console.error("❌ CI policy: Protected paths changed but no 'Approved-By:' trailer.");
    console.error("Changed files:", files.join(", "));
    process.exit(2);
  }
}
console.log("✅ CI policy passed");
