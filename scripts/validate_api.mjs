import { spawn } from "node:child_process";
const url = process.env.HEALTH_URL || "http://localhost:3002/health";
const curl = spawn("curl", ["-fsS", "--max-time", "5", url], { stdio: "inherit" });
curl.on("exit", (code)=>process.exit(code===0?0:1));
