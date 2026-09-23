'use strict';

// Shared startup/shutdown helpers for the backend entry points.
// Every stage logs an explicit OK / FAILED result so a failed run
// always points at the stage that broke instead of a raw stack trace.

function stageOk(stage, message) {
  console.log(`[${stage}] OK - ${message}`);
}

function stageFail(stage, message) {
  console.error(`[${stage}] FAILED - ${message}`);
}

// Verify that required packages can actually be loaded (including
// native bindings like better-sqlite3) before the real modules are
// required, so a broken install fails here with a clear message.
function checkDependencies(stage, deps) {
  const broken = [];
  for (const dep of deps) {
    try {
      require(dep);
    } catch (err) {
      broken.push(`${dep} (${err.code || err.message})`);
    }
  }
  if (broken.length > 0) {
    stageFail(stage, `cannot load: ${broken.join(', ')}. Run "npm install" in the backend directory first.`);
    process.exit(1);
  }
  stageOk(stage, `${deps.length} dependencies loadable`);
}

// Validate the configured port; an invalid PORT must stop startup
// here instead of surfacing as a confusing listen() error later.
function parsePort(raw, fallback) {
  if (raw === undefined || raw === '') {
    return fallback;
  }
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    stageFail('config', `invalid PORT "${raw}"; expected an integer between 1 and 65535`);
    process.exit(1);
  }
  return port;
}

module.exports = { stageOk, stageFail, checkDependencies, parsePort };
