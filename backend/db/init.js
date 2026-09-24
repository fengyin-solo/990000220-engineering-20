const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

const DB_DIR = path.join(__dirname, '..', 'data');
const DB_PATH = path.join(DB_DIR, 'blog.db');

let db;

// Create the storage directory if needed and verify it is writable.
// Throws a descriptive error (stage: storage) when the directory is unusable.
function ensureStorage() {
  try {
    fs.mkdirSync(DB_DIR, { recursive: true });
  } catch (err) {
    const error = new Error(`Cannot create storage directory ${DB_DIR}: ${err.message}`);
    error.stage = 'storage';
    throw error;
  }

  try {
    fs.accessSync(DB_DIR, fs.constants.R_OK | fs.constants.W_OK);
  } catch (err) {
    const error = new Error(`Storage directory is not writable: ${DB_DIR}`);
    error.stage = 'storage';
    throw error;
  }

  // Probe write access: on some platforms fs.access alone is not enough.
  const probe = path.join(DB_DIR, '.write-test');
  try {
    fs.writeFileSync(probe, 'ok');
    fs.unlinkSync(probe);
  } catch (err) {
    const error = new Error(`Storage directory is not writable: ${DB_DIR} (${err.message})`);
    error.stage = 'storage';
    throw error;
  }

  return DB_DIR;
}

function getDb() {
  if (!db) {
    ensureStorage();
    try {
      db = new Database(DB_PATH);
      db.pragma('journal_mode = WAL');
    } catch (err) {
      const error = new Error(`Failed to open database at ${DB_PATH}: ${err.message}`);
      error.stage = 'database';
      throw error;
    }
  }
  return db;
}

function initDb() {
  const database = getDb();

  try {
    database.exec(`
      CREATE TABLE IF NOT EXISTS articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        summary TEXT,
        tags TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);
  } catch (err) {
    const error = new Error(`Failed to initialize database schema: ${err.message}`);
    error.stage = 'database';
    throw error;
  }

  return database;
}

function closeDb() {
  if (db) {
    try {
      db.close();
    } finally {
      db = undefined;
    }
  }
}

module.exports = initDb;
module.exports.getDb = getDb;
module.exports.closeDb = closeDb;
module.exports.ensureStorage = ensureStorage;
module.exports.DB_PATH = DB_PATH;
module.exports.DB_DIR = DB_DIR;

// Allow running the migration directly: `node db/init.js`
if (require.main === module) {
  try {
    ensureStorage();
    initDb();
    console.log(`[init] storage ready: ${DB_DIR}`);
    console.log('[init] database initialized successfully');
    closeDb();
    process.exit(0);
  } catch (err) {
    console.error(`[init][FAIL:${err.stage || 'database'}] ${err.message}`);
    closeDb();
    process.exit(1);
  }
}
