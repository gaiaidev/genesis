#!/usr/bin/env node

import fs from 'fs/promises';
import path from 'path';

async function lastMileCheck() {
  console.log('[LAST-MILE] Starting final verification...');
  
  const reportPath = 'artifacts/reports/ci_fail_report.json';
  const report = JSON.parse(await fs.readFile(reportPath, 'utf8'));
  
  const failCount = report.filter(r => !r.ok).length;
  const passCount = report.filter(r => r.ok).length;
  const total = report.length;
  
  const passRate = passCount / total;
  
  console.log(`[LAST-MILE] Files: ${total}`);
  console.log(`[LAST-MILE] Pass: ${passCount} (${(passRate * 100).toFixed(2)}%)`);
  console.log(`[LAST-MILE] Fail: ${failCount}`);
  
  const result = {
    timestamp: new Date().toISOString(),
    files_total: total,
    files_pass: passCount,
    files_fail: failCount,
    pass_rate: passRate,
    status: passRate >= 0.9 ? 'PASS' : 'FAIL'
  };
  
  await fs.writeFile(
    'artifacts/reports/last_mile_result.json',
    JSON.stringify(result, null, 2)
  );
  
  console.log(`[LAST-MILE] Result: ${result.status}`);
  return result;
}

lastMileCheck().catch(console.error);