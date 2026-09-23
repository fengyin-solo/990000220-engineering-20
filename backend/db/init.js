const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const DB_DIR = path.join(__dirname, '..', 'data');
const DB_PATH = path.join(DB_DIR, 'blog.db');

let db;

// The data directory must exist and be writable before SQLite tries
// to open the database file, otherwise the driver fails with a
// generic "unable to open database file" error.
function ensureDataDir() {
  try {
    fs.mkdirSync(DB_DIR, { recursive: true });
    fs.accessSync(DB_DIR, fs.constants.W_OK);
  } catch (err) {
    throw new Error(`storage directory ${DB_DIR} is not writable (${err.code || err.message})`);
  }
}

function getDb() {
  if (!db) {
    ensureDataDir();
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
  }
  return db;
}

function initDb() {
  const database = getDb();

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

  return database;
}

// Release the database handle so the process can exit cleanly and
// WAL files are checkpointed instead of left behind.
function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}

module.exports = initDb;
module.exports.getDb = getDb;
module.exports.closeDb = closeDb;
module.exports.DB_PATH = DB_PATH;
