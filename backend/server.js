// --- Stage 1: configuration ----------------------------------------------
const PORT = Number.parseInt(process.env.PORT, 10);
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) {
  console.error(`[server][FAIL:config] invalid PORT "${process.env.PORT}" (must be 1-65535)`);
  process.exit(1);
}

// --- Stage 2: dependencies ------------------------------------------------
let express, cors, initDb, getDb, closeDb, articlesRouter, authRouter;
try {
  express = require('express');
  cors = require('cors');
  ({ closeDb } = require('./db/init'));
  initDb = require('./db/init');
  articlesRouter = require('./routes/articles');
  authRouter = require('./routes/auth');
} catch (err) {
  if (err.code === 'MODULE_NOT_FOUND') {
    const match = /Cannot find module '([^']+)'/.exec(err.message);
    console.error(`[server][FAIL:dependencies] missing dependency "${match ? match[1] : err.message.split('\n')[0]}". Run "npm install" in the backend directory first.`);
  } else {
    console.error(`[server][FAIL:dependencies] ${err.message}`);
  }
  process.exit(1);
}

// --- Stage 3: storage + database -------------------------------------------
try {
  initDb();
} catch (err) {
  console.error(`[server][FAIL:${err.stage || 'database'}] ${err.message}`);
  process.exit(1);
}

// --- Stage 4: application wiring -------------------------------------------
const app = express();

app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', authRouter);
app.use('/api/articles', articlesRouter);

// Tags route
const { getTags } = require('./routes/articles');
app.get('/api/tags', getTags);

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

// --- Stage 5: listen -------------------------------------------------------
let server;
let shuttingDown = false;

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[server] received ${signal}, shutting down...`);

  if (server) {
    server.close(() => {
      closeDb();
      console.log('[server] http server and database closed, cleanup done');
      process.exit(0);
    });
    // Do not wait forever on keep-alive connections
    setTimeout(() => {
      closeDb();
      console.warn('[server] forced shutdown after timeout');
      process.exit(1);
    }, 5000).unref();
  } else {
    closeDb();
    process.exit(0);
  }
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

try {
  server = app.listen(PORT, () => {
    console.log(`[server] listening on http://localhost:${PORT}`);
  });
} catch (err) {
  console.error(`[server][FAIL:listen] ${err.message}`);
  closeDb();
  process.exit(1);
}

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[server][FAIL:listen] port ${PORT} is already in use. Free the port or set PORT=<other>.`);
  } else {
    console.error(`[server][FAIL:listen] ${err.message}`);
  }
  closeDb();
  process.exit(1);
});
