const { checkDependencies, parsePort, stageOk, stageFail } = require('./lib/startup');

// Stage: dependency check (before loading any third-party module)
checkDependencies('deps', ['express', 'cors', 'better-sqlite3', 'jsonwebtoken']);

const express = require('express');
const cors = require('cors');
const initDb = require('./db/init');
const { closeDb, DB_PATH } = require('./db/init');
const articlesRouter = require('./routes/articles');
const authRouter = require('./routes/auth');
const { getTags } = require('./routes/articles');

// Stage: port configuration
const PORT = parsePort(process.env.PORT, 3001);
stageOk('config', `port ${PORT}`);

// Stage: database initialization
try {
  initDb();
  stageOk('db', `database ready at ${DB_PATH}`);
} catch (err) {
  stageFail('db', err.message);
  process.exit(1);
}

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', authRouter);
app.use('/api/articles', articlesRouter);
app.get('/api/tags', getTags);

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

// Stage: HTTP server startup
const server = app.listen(PORT);

server.on('listening', () => {
  stageOk('server', `listening on http://localhost:${PORT}`);
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    stageFail('server', `port ${PORT} is already in use; stop the leftover process or set PORT to a free port`);
  } else {
    stageFail('server', err.message);
  }
  process.exit(1);
});

// Stage: shutdown cleanup - release the port and the database handle
// so a restarted process does not hit a stale listener or WAL locks.
let shuttingDown = false;

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[cleanup] received ${signal}, closing server and database...`);
  server.close(() => {
    closeDb();
    stageOk('cleanup', 'port released and database closed');
    process.exit(0);
  });
  setTimeout(() => {
    stageFail('cleanup', 'timed out while closing, forcing exit');
    process.exit(1);
  }, 5000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
