// Simple assertion helpers — no test framework needed

let _passed = 0;
let _failed = 0;
let _errors = [];

export function eq(actual, expected, label) {
  if (actual === expected) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function neq(actual, notExpected, label) {
  if (actual !== notExpected) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — expected NOT ${JSON.stringify(notExpected)}`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function ok(value, label) {
  if (value) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — expected truthy, got ${JSON.stringify(value)}`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function includes(arr, value, label) {
  if (Array.isArray(arr) && arr.includes(value)) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — ${JSON.stringify(value)} not found in array`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function gte(actual, expected, label) {
  if (actual >= expected) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — expected >= ${expected}, got ${actual}`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function lte(actual, expected, label) {
  if (actual <= expected) {
    _passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
  } else {
    _failed++;
    const msg = `${label} — expected <= ${expected}, got ${actual}`;
    _errors.push(msg);
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

export function resetCounters() {
  _passed = 0;
  _failed = 0;
  _errors = [];
}

export function getResults() {
  return { passed: _passed, failed: _failed, errors: [..._errors] };
}
