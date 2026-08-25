import { setup, ctx } from './lib/fixtures.js';
import { cleanup } from './lib/cleanup.js';
import { resetCounters, getResults } from './lib/assert.js';

const suiteFiles = [
  '01-auth-boundaries.js',
  '02-submit-bets.js',
  '03-submit-parlay.js',
  '04-idempotency.js',
  '05-grading.js',
  '06-settlement.js',
  '07-override.js',
  '08-balance-adjust.js',
  '09-ledger-integrity.js',
  '10-concurrent-bets.js',
  '11-concurrent-settle.js',
  '12-invite-flow.js',
  '13-accept-decline.js',
  '14-credit-limits.js',
  '15-win-limits.js',
  '16-invite-email-flow.js',
];

// Allow running a single suite: node runner.js 05
const filter = process.argv[2];

async function main() {
  const startTime = Date.now();
  let totalPassed = 0;
  let totalFailed = 0;
  const suiteResults = [];

  try {
    await setup();

    for (const file of suiteFiles) {
      if (filter && !file.startsWith(filter)) continue;

      resetCounters();
      const suiteStart = Date.now();
      const suiteName = file.replace('.js', '');

      console.log(`\x1b[36m━━━ ${suiteName} ━━━\x1b[0m`);

      try {
        const mod = await import(`./suites/${file}`);
        await mod.default(ctx);
      } catch (err) {
        console.log(`  \x1b[31m✗ SUITE ERROR: ${err.message}\x1b[0m`);
        if (err.stack) console.log(`    ${err.stack.split('\n').slice(1, 3).join('\n    ')}`);
      }

      const { passed, failed, errors } = getResults();
      const elapsed = Date.now() - suiteStart;
      const status = failed === 0 ? '\x1b[32mPASS\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
      console.log(`  ${status} ${passed} passed, ${failed} failed (${elapsed}ms)\n`);

      totalPassed += passed;
      totalFailed += failed;
      suiteResults.push({ name: suiteName, passed, failed, elapsed });
    }
  } finally {
    await cleanup();
  }

  // Summary
  const totalElapsed = Date.now() - startTime;
  console.log('\x1b[36m━━━ SUMMARY ━━━\x1b[0m');
  for (const s of suiteResults) {
    const icon = s.failed === 0 ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m';
    console.log(`  ${icon} ${s.name}: ${s.passed} passed, ${s.failed} failed (${s.elapsed}ms)`);
  }
  console.log(`\n  Total: ${totalPassed} passed, ${totalFailed} failed (${(totalElapsed / 1000).toFixed(1)}s)`);

  if (totalFailed > 0) {
    console.log('\n\x1b[31mSome tests failed.\x1b[0m');
    process.exit(1);
  } else {
    console.log('\n\x1b[32mAll tests passed!\x1b[0m');
  }
}

main().catch(err => {
  console.error('\x1b[31mFatal error:\x1b[0m', err);
  cleanup().finally(() => process.exit(1));
});
