const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');
const EmbeddedPostgresModule = require('embedded-postgres');
const { env } = require('./env');

const EmbeddedPostgres = EmbeddedPostgresModule.default || EmbeddedPostgresModule;

let pool = null;
let embeddedPostgres = null;
let initialized = false;
let initPromise = null;

const schemaPath = path.resolve(process.cwd(), 'db', 'schema.sql');

const getPool = () => {
  if (!pool) {
    throw new Error('Database is not initialized');
  }

  return pool;
};

const registerPoolErrorHandler = (nextPool) => {
  nextPool.on('error', (error) => {
    console.error('Unexpected database error', error);
  });
};

const quoteIdentifier = (value) => `"${String(value).replace(/"/g, '""')}"`;

const buildEmbeddedConnectionString = (databaseName) =>
  `postgres://${encodeURIComponent(env.EMBEDDED_DB_USER)}:${encodeURIComponent(
    env.EMBEDDED_DB_PASSWORD,
  )}@127.0.0.1:${env.EMBEDDED_DB_PORT}/${encodeURIComponent(databaseName)}`;

const getDatabaseEncoding = async (client, databaseName) => {
  const result = await client.query(
    `
      SELECT pg_encoding_to_char(encoding) AS encoding
      FROM pg_database
      WHERE datname = $1
      LIMIT 1
    `,
    [databaseName],
  );

  return result.rows[0]?.encoding || null;
};

const createUtf8Database = async (client, databaseName) => {
  await client.query(
    `CREATE DATABASE ${quoteIdentifier(databaseName)} WITH ENCODING 'UTF8' TEMPLATE template0`,
  );
};

const ensureEmbeddedDatabaseName = async (client, preferredName) => {
  const preferredEncoding = await getDatabaseEncoding(client, preferredName);

  if (!preferredEncoding) {
    await createUtf8Database(client, preferredName);
    return preferredName;
  }

  if (preferredEncoding === 'UTF8') {
    return preferredName;
  }

  const utf8Name = preferredName.endsWith('_utf8') ? preferredName : `${preferredName}_utf8`;
  const utf8Encoding = await getDatabaseEncoding(client, utf8Name);

  if (!utf8Encoding) {
    await createUtf8Database(client, utf8Name);
  } else if (utf8Encoding !== 'UTF8') {
    throw new Error(
      `Embedded database "${utf8Name}" exists with unsupported encoding "${utf8Encoding}"`,
    );
  }

  console.warn(
    `Embedded database "${preferredName}" uses ${preferredEncoding}; falling back to "${utf8Name}" (UTF8).`,
  );

  return utf8Name;
};

const startEmbeddedDatabase = async () => {
  const databaseDir = path.resolve(process.cwd(), env.EMBEDDED_DB_DIR);
  const pgVersionPath = path.join(databaseDir, 'PG_VERSION');
  fs.mkdirSync(databaseDir, { recursive: true });

  embeddedPostgres = new EmbeddedPostgres({
    databaseDir,
    user: env.EMBEDDED_DB_USER,
    password: env.EMBEDDED_DB_PASSWORD,
    port: env.EMBEDDED_DB_PORT,
    persistent: true,
    initdbFlags: ['--encoding=UTF8', '--locale=C'],
    onLog: () => {},
  });

  if (!fs.existsSync(pgVersionPath)) {
    await embeddedPostgres.initialise();
  }

  await embeddedPostgres.start();

  const adminClient = embeddedPostgres.getPgClient('postgres', '127.0.0.1');

  try {
    await adminClient.connect();
    const databaseName = await ensureEmbeddedDatabaseName(adminClient, env.EMBEDDED_DB_NAME);
    return buildEmbeddedConnectionString(databaseName);
  } finally {
    await adminClient.end();
  }
};

const applySchema = async () => {
  if (!env.DB_AUTO_SCHEMA && !env.USE_EMBEDDED_POSTGRES) {
    return;
  }

  const schemaSql = fs.readFileSync(schemaPath, 'utf8');
  await getPool().query(schemaSql);
};

const initializeDatabase = async () => {
  if (initialized) {
    return;
  }

  if (initPromise) {
    await initPromise;
    return;
  }

  initPromise = (async () => {
    const connectionString = env.USE_EMBEDDED_POSTGRES
      ? await startEmbeddedDatabase()
      : env.DATABASE_URL;

    pool = new Pool({
      connectionString,
      ssl: env.USE_EMBEDDED_POSTGRES ? false : env.DB_SSL ? { rejectUnauthorized: false } : false,
    });

    registerPoolErrorHandler(pool);
    await pool.query('SELECT 1');
    await applySchema();
    initialized = true;
  })();

  try {
    await initPromise;
  } catch (error) {
    if (pool) {
      await pool.end();
      pool = null;
    }

    if (embeddedPostgres) {
      await embeddedPostgres.stop();
      embeddedPostgres = null;
    }

    throw error;
  } finally {
    initPromise = null;
  }
};

const query = (text, params) => getPool().query(text, params);

const withTransaction = async (handler) => {
  const client = await getPool().connect();

  try {
    await client.query('BEGIN');
    const result = await handler(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
};

const shutdownDatabase = async () => {
  if (pool) {
    await pool.end();
    pool = null;
  }

  if (embeddedPostgres) {
    await embeddedPostgres.stop();
    embeddedPostgres = null;
  }

  initialized = false;
};

module.exports = {
  initializeDatabase,
  shutdownDatabase,
  query,
  withTransaction,
};
