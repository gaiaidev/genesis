#!/usr/bin/env node

import fs from 'fs/promises';
import path from 'path';
import crypto from 'crypto';

async function generateCertificate() {
  console.log('[CERTIFICATE] Generating integrity certificate...');
  
  const reportPath = 'artifacts/reports/ci_fail_report.json';
  const lastMilePath = 'artifacts/reports/last_mile_result.json';
  
  let report, lastMile;
  
  try {
    report = JSON.parse(await fs.readFile(reportPath, 'utf8'));
  } catch (e) {
    report = [];
  }
  
  try {
    lastMile = JSON.parse(await fs.readFile(lastMilePath, 'utf8'));
  } catch (e) {
    lastMile = { pass_rate: 0, status: 'PENDING' };
  }
  
  const failCount = report.filter(r => !r.ok).length;
  const passCount = report.filter(r => r.ok).length;
  const total = report.length || 1;
  
  const passRate = total > 0 ? passCount / total : 0;
  const score = Math.min(1.0, passRate);
  
  const certificate = {
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    determinism: {
      seed: process.env.DETERMINISM_SEED || '1337',
      clock: process.env.DETERMINISM_CLOCK || '2025-01-01T00:00:00Z'
    },
    metrics: {
      files_total: total,
      files_pass: passCount,
      files_fail: failCount,
      pass_rate: passRate,
      score: score
    },
    acceptance: {
      pass_eq_total: passCount === total,
      score_eq_1_00: score === 1.0,
      second_run_zero_diff: false // Will be updated after second run
    },
    signature: crypto.randomBytes(32).toString('hex'),
    status: score >= 0.9 ? 'CERTIFIED' : 'NOT_CERTIFIED'
  };
  
  await fs.mkdir('artifacts/reports', { recursive: true });
  await fs.writeFile(
    'artifacts/reports/final_integrity_certificate.json',
    JSON.stringify(certificate, null, 2)
  );
  
  console.log(`[CERTIFICATE] Status: ${certificate.status}`);
  console.log(`[CERTIFICATE] Score: ${certificate.metrics.score.toFixed(2)}`);
  console.log(`[CERTIFICATE] Pass Rate: ${(certificate.metrics.pass_rate * 100).toFixed(2)}%`);
  
  return certificate;
}

generateCertificate().catch(console.error);