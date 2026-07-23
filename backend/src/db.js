import mysql from "mysql2/promise";

import * as config from "./config.js";

// On Cloud Run, CROPLOO_DB_SOCKET_PATH points at the Cloud SQL Auth Proxy's
// Unix socket; locally, connect over TCP instead.
const connectionOptions = config.DB_SOCKET_PATH
  ? { socketPath: config.DB_SOCKET_PATH, user: config.DB_USER, password: config.DB_PASSWORD }
  : { host: config.DB_HOST, port: config.DB_PORT, user: config.DB_USER, password: config.DB_PASSWORD };

export const pool = mysql.createPool({
  ...connectionOptions,
  database: config.DB_NAME,
  charset: "utf8mb4",
  waitForConnections: true,
  connectionLimit: 10,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0,
});

/**
 * Initialize database schema - call this after server starts.
 */
export async function initializeDatabase() {
  let serverConn;
  try {
    serverConn = await mysql.createConnection(connectionOptions);
    await serverConn.query(
      `CREATE DATABASE IF NOT EXISTS \`${config.DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
    );
    await serverConn.end();
  } catch (error) {
    console.error("Failed to connect to database during initialization:", error.message);
    // Don't throw - allow server to continue
  }

  /**
   * This database predates this backend (an earlier, never-fully-wired
   * implementation already created several of these tables under the
   * same names but with different columns — e.g. `alerts.alert_type`
   * instead of `alerts.type`). `CREATE TABLE IF NOT EXISTS` alone can't
   * patch an existing table, so for each one we: add any columns this
   * backend needs that are missing, relax any of the *other* table's
   * NOT-NULL-without-default columns that this backend's INSERTs don't
   * populate (rather than fabricating values for them), and add the
   * unique index this backend's ON DUPLICATE KEY UPDATE upserts rely on.
   */
  async function patchLegacyTable(table, { addColumns = {}, relaxColumns = [], uniqueKey } = {}) {
    const [existing] = await pool.query(
      `SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_TYPE FROM information_schema.COLUMNS
       WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?`,
      [config.DB_NAME, table]
    );
    const columns = new Map(existing.map((c) => [c.COLUMN_NAME, c]));

    for (const [name, definition] of Object.entries(addColumns)) {
      if (!columns.has(name)) {
        await pool.query(`ALTER TABLE ${table} ADD COLUMN ${name} ${definition}`);
      }
    }

    for (const name of relaxColumns) {
      const info = columns.get(name);
      if (info?.IS_NULLABLE === "NO") {
        await pool.query(`ALTER TABLE ${table} MODIFY COLUMN ${name} ${info.COLUMN_TYPE} NULL`);
      }
    }

    if (uniqueKey) {
      const [indexes] = await pool.query(
        `SELECT INDEX_NAME FROM information_schema.STATISTICS
         WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME = ?`,
        [config.DB_NAME, table, uniqueKey.name]
      );
      if (indexes.length === 0) {
        await pool.query(`ALTER TABLE ${table} ADD UNIQUE KEY ${uniqueKey.name} (${uniqueKey.columns})`);
      }
    }
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      username VARCHAR(32) UNIQUE NOT NULL,
      name VARCHAR(120) DEFAULT '',
      password_hash VARCHAR(255) NOT NULL,
      subscription_tier VARCHAR(16) DEFAULT 'free',
      is_verified BOOLEAN NOT NULL DEFAULT FALSE,
      verification_code VARCHAR(8) DEFAULT NULL,
      verification_expires DATETIME DEFAULT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // `users` may already exist from the old Python backend's schema, which
  // lacks the columns this backend needs — CREATE TABLE IF NOT EXISTS alone
  // won't patch that, so add them idempotently. MySQL has no ADD COLUMN IF
  // NOT EXISTS (that's a MariaDB-only extension), so check first.
  const [existingColumns] = await pool.query(
    `SELECT COLUMN_NAME FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'users'`,
    [config.DB_NAME]
  );
  const columnNames = new Set(existingColumns.map((c) => c.COLUMN_NAME));

  if (!columnNames.has("username")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN username VARCHAR(32) NOT NULL DEFAULT '', ADD UNIQUE INDEX username (username)`
    );
  }
  if (!columnNames.has("is_verified")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE`
    );
  }
  if (!columnNames.has("verification_code")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN verification_code VARCHAR(8) DEFAULT NULL`
    );
  }
  if (!columnNames.has("verification_expires")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN verification_expires DATETIME DEFAULT NULL`
    );
  }
  if (!columnNames.has("daily_brief_email")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN daily_brief_email BOOLEAN NOT NULL DEFAULT TRUE`
    );
  }
  if (!columnNames.has("referred_by")) {
    await pool.query(`ALTER TABLE users ADD COLUMN referred_by INT DEFAULT NULL`);
  }
  if (!columnNames.has("stripe_customer_id")) {
    await pool.query(`ALTER TABLE users ADD COLUMN stripe_customer_id VARCHAR(255) DEFAULT NULL`);
  }
  if (!columnNames.has("trial_ends_at")) {
    await pool.query(`ALTER TABLE users ADD COLUMN trial_ends_at DATETIME DEFAULT NULL`);
  }
  if (!columnNames.has("has_used_trial")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN has_used_trial BOOLEAN NOT NULL DEFAULT FALSE`
    );
  }
  // Separate from verification_code/verification_expires (email-verify
  // flow above) so a password reset request can never invalidate a
  // pending email-verification code, or vice versa.
  if (!columnNames.has("reset_code")) {
    await pool.query(`ALTER TABLE users ADD COLUMN reset_code VARCHAR(8) DEFAULT NULL`);
  }
  if (!columnNames.has("reset_expires")) {
    await pool.query(`ALTER TABLE users ADD COLUMN reset_expires DATETIME DEFAULT NULL`);
  }
  // Old Python schema's created_at has no default, but inserts here don't set it.
  await pool.query(
    `ALTER TABLE users MODIFY COLUMN created_at DATETIME DEFAULT CURRENT_TIMESTAMP`
  );

  // Team Accounts — columns added when the feature launched.
  if (!columnNames.has("team_id")) {
    await pool.query(`ALTER TABLE users ADD COLUMN team_id INT DEFAULT NULL`);
  }
  if (!columnNames.has("team_role")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN team_role ENUM('admin','member') DEFAULT NULL`
    );
  }
  // Grandfathering — stores the tier the user was eligible for at the old
  // price. NULL means the user registered after the price increase and pays
  // the current rate.
  if (!columnNames.has("grandfathered_tier")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN grandfathered_tier VARCHAR(16) DEFAULT NULL`
    );
  }
  // Founding-member promo — set at registration time for the first 50
  // signups (see the atomic counter claim in routes/auth.js). Grants 50%
  // off for life via a Stripe coupon applied at checkout.
  if (!columnNames.has("founding_member")) {
    await pool.query(
      `ALTER TABLE users ADD COLUMN founding_member BOOLEAN NOT NULL DEFAULT FALSE`
    );
  }

  // Single-row-per-name counters for promos like the founding-member
  // discount. Claiming a slot is a `SELECT ... FOR UPDATE` + increment
  // inside a transaction (see routes/auth.js), so concurrent signups can't
  // both claim the last slot.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS promo_counters (
      name VARCHAR(64) PRIMARY KEY,
      count INT NOT NULL DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS futures_prices (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL UNIQUE,
      name VARCHAR(64) NOT NULL,
      contract_month VARCHAR(8) DEFAULT '',
      price DOUBLE NOT NULL,
      \`change\` DOUBLE DEFAULT 0,
      change_pct DOUBLE DEFAULT 0,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS futures_price_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      bar_date DATE NOT NULL,
      close DOUBLE NOT NULL,
      UNIQUE KEY uniq_symbol_date (symbol, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real cash/futures/basis bars from USDA AMS AgTransport, one row per
  // state market + commodity + week (see src/usdaBasis.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS basis_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      state VARCHAR(2) NOT NULL,
      symbol VARCHAR(8) NOT NULL,
      cash_price DOUBLE NOT NULL,
      futures_price DOUBLE NOT NULL,
      basis DOUBLE NOT NULL,
      snapshot_date DATE NOT NULL,
      UNIQUE KEY uniq_state_symbol_date (state, symbol, snapshot_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
  await patchLegacyTable("basis_snapshots", {
    addColumns: {
      state: "VARCHAR(2) NOT NULL DEFAULT ''",
      symbol: "VARCHAR(8) NOT NULL DEFAULT ''",
      cash_price: "DOUBLE NOT NULL DEFAULT 0",
      futures_price: "DOUBLE NOT NULL DEFAULT 0",
      basis: "DOUBLE NOT NULL DEFAULT 0",
      snapshot_date: "DATE NULL",
    },
    relaxColumns: ["elevator_id", "commodity_symbol", "basis_value", "avg_5yr"],
    uniqueKey: { name: "uniq_state_symbol_date", columns: "state, symbol, snapshot_date" },
  });

  // Alerts generated by alertsEngine.js from real basis/futures data. Not
  // user-scoped: the app has no per-user watchlist/personalization yet, so
  // every alert is shown to every user (matching the existing UI, which
  // already renders one shared alert feed).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS alerts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      type ENUM('BASIS_ANOMALY','USDA_RELEASE','FUTURES_MOVE') NOT NULL,
      commodity ENUM('CORN','WHEAT','SOYBEANS','ALL') NOT NULL DEFAULT 'ALL',
      title VARCHAR(255) NOT NULL,
      body TEXT,
      severity ENUM('LOW','MEDIUM','HIGH') NOT NULL,
      is_read BOOLEAN DEFAULT FALSE,
      metadata JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
  await patchLegacyTable("alerts", {
    addColumns: {
      type: "VARCHAR(20) NOT NULL DEFAULT 'BASIS_ANOMALY'",
      commodity: "VARCHAR(16) NOT NULL DEFAULT 'ALL'",
      severity: "VARCHAR(8) NOT NULL DEFAULT 'MEDIUM'",
      metadata: "JSON DEFAULT NULL",
      created_at: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
    },
    relaxColumns: ["user_id", "alert_type", "priority", "triggered_at", "is_read"],
  });

  // Real weekly retail diesel prices per PADD region (EIA), used as the
  // fuel-cost input for the freight index (see src/eiaFreight.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS diesel_prices (
      id INT AUTO_INCREMENT PRIMARY KEY,
      region VARCHAR(8) NOT NULL,
      bar_date DATE NOT NULL,
      price DOUBLE NOT NULL,
      UNIQUE KEY uniq_region_date (region, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // USDA reports: real NASS data (raw_data) plus Claude's cached
  // narrative analysis (ai_json) — see src/usdaReports.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS usda_reports (
      id INT AUTO_INCREMENT PRIMARY KEY,
      report_type ENUM('WASDE','CROP_PROGRESS','EXPORT_SALES') NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      title VARCHAR(255) NOT NULL,
      release_date DATE NOT NULL,
      raw_data JSON,
      ai_processed_at DATETIME DEFAULT NULL,
      ai_json JSON DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_report (report_type, commodity, release_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
  await patchLegacyTable("usda_reports", {
    addColumns: {
      commodity: "VARCHAR(16) NOT NULL DEFAULT ''",
      raw_data: "JSON DEFAULT NULL",
      ai_json: "JSON DEFAULT NULL",
      created_at: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
    },
    relaxColumns: [
      "ai_headline", "ai_direction", "ai_summary", "ai_key_points",
      "commodity_impacts", "risk_factors", "basis_impact", "confidence", "comparison_title", "comparison",
    ],
    uniqueKey: { name: "uniq_report", columns: "report_type, commodity, release_date" },
  });

  // One Claude-synthesized daily brief per calendar day, built from that
  // day's real basis/futures/alert/USDA data (see src/dailyBrief.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS daily_briefs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      brief_date DATE NOT NULL UNIQUE,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Weekly CFTC COT snapshots plus Claude's cached translation
  // (see src/cotData.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cot_reports (
      id INT AUTO_INCREMENT PRIMARY KEY,
      report_date DATE NOT NULL UNIQUE,
      raw_data JSON,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily NOAA Corn Belt precipitation anomalies plus Claude's cached
  // market-implication readout (see src/weatherImpact.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS weather_impacts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      impact_date DATE NOT NULL UNIQUE,
      raw_data JSON,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Pro Farmer vs USDA yield comparison, one Claude analysis per
  // commodity + tour year (see src/cropTour.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS crop_tour_analyses (
      id INT AUTO_INCREMENT PRIMARY KEY,
      commodity VARCHAR(16) NOT NULL,
      tour_year INT NOT NULL,
      raw_data JSON,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_commodity_year (commodity, tour_year)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily soybean board-crush bars computed from front-month ZS/ZL/ZM
  // closes (see src/crushSpread.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS crush_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      bar_date DATE NOT NULL UNIQUE,
      zs_close DOUBLE NOT NULL,
      zl_close DOUBLE NOT NULL,
      zm_close DOUBLE NOT NULL,
      crush DOUBLE NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // ~10y of weekly continuous-futures closes from Yahoo Finance, used only
  // for seasonal.js's index-vs-week-of-year pattern (Alpha Vantage's free
  // tier no longer allows outputsize=full, so this can't reuse
  // futures_price_history).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS seasonal_price_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      bar_date DATE NOT NULL,
      close DOUBLE NOT NULL,
      UNIQUE KEY uniq_symbol_date (symbol, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Per-user watchlist of commodity+state combos — basis data is
  // state-level (see usdaBasis.js), so that's the natural watchlist
  // granularity ("Iowa Corn"), not per-elevator.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS watchlist_items (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      state VARCHAR(2) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_user_commodity_state (user_id, commodity, state)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // User-defined alert thresholds, scanned by alertsEngine.js alongside
  // the fixed system rules. Personal alerts they trigger are inserted
  // into `alerts` with user_id set (see the alerts table's user_id column,
  // already relaxed to nullable above for exactly this).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS custom_alert_rules (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      rule_type ENUM('BASIS_THRESHOLD','FUTURES_MOVE_THRESHOLD') NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      state VARCHAR(2) NULL,
      comparison ENUM('BELOW','ABOVE') NOT NULL,
      threshold_value DOUBLE NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // User price targets (e.g. "sell corn above $5.20") — scanned against
  // real futures_prices by alertsEngine.js, fires once then deactivates.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS price_targets (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      symbol VARCHAR(8) NOT NULL,
      target_price DOUBLE NOT NULL,
      direction ENUM('ABOVE','BELOW') NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      triggered_at DATETIME NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // User grain inventory positions — P&L, sell-window, and hedge
  // suggestions are computed live from real basis/seasonal/COT data (see
  // src/portfolio.js), never stored.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS portfolio_positions (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      bushels DOUBLE NOT NULL,
      stored_date DATE NOT NULL,
      break_even_price DOUBLE NOT NULL,
      state VARCHAR(2) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Per-user daily brief variant for users with a watchlist — emphasizes
  // their watched commodity+state combos instead of the generic market-
  // wide brief (daily_briefs above). Kept as its own table rather than
  // widening daily_briefs' unique key, since that table's already live.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS personalized_daily_briefs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      brief_date DATE NOT NULL,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_user_date (user_id, brief_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily CullyAI message counts, used to enforce the Basic-plan message cap.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cullyai_usage (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      message_count INT DEFAULT 0,
      date DATE NOT NULL,
      UNIQUE KEY unique_user_date (user_id, date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Current forward-curve snapshot per symbol+contract month, real prices
  // from Yahoo Finance's individual CME contract-month tickers (see
  // src/forwardCurve.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS forward_curve (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      contract_month VARCHAR(8) NOT NULL,
      expiry_date DATE NOT NULL,
      price DOUBLE NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_symbol_contract (symbol, contract_month)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily near/far calendar-spread snapshots, so the spread's trend over
  // time is trackable, not just its current level.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS calendar_spread_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      near_month VARCHAR(8) NOT NULL,
      far_month VARCHAR(8) NOT NULL,
      spread DOUBLE NOT NULL,
      bar_date DATE NOT NULL,
      UNIQUE KEY uniq_symbol_date (symbol, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Claude's cached forward-curve storage-economics readout, one per
  // symbol per day.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS forward_curve_analysis (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      analysis_date DATE NOT NULL,
      ai_json JSON,
      UNIQUE KEY uniq_symbol_date (symbol, analysis_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily corn-to-ethanol board margin, from real Yahoo Finance closes
  // (EH=F ethanol futures, ZC=F corn futures) — same simplified two-leg
  // approach as the soybean crush (crush_history), ignoring DDGS
  // byproduct credit and processing costs.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ethanol_margin_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      bar_date DATE NOT NULL UNIQUE,
      corn_close DOUBLE NOT NULL,
      ethanol_close DOUBLE NOT NULL,
      margin DOUBLE NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily US Dollar Index proxy (UUP ETF) paired with corn futures (ZC=F),
  // both real Yahoo Finance closes, for the dollar/export-competitiveness
  // correlation read (see src/dollarIndex.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS dollar_index_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      bar_date DATE NOT NULL UNIQUE,
      dollar_index DOUBLE NOT NULL,
      corn_price DOUBLE NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real daily Henry Hub natural gas futures (NG=F) closes — a plain
  // price series for correlationMatrix.js, distinct from the weekly
  // storage-in-Bcf figure in ng_storage_snapshots. See src/ngPrice.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ng_price_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      bar_date DATE NOT NULL UNIQUE,
      close DOUBLE NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily 3:2:1 crack spread (oil refining margin) computed from real
  // front-month CL/RB/HO closes, plus Claude's cached read for whenever a
  // reading is unusually wide/narrow vs its own trailing average — see
  // src/crackSpread.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS crack_spread_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      bar_date DATE NOT NULL UNIQUE,
      crude_close DOUBLE NOT NULL,
      gasoline_close DOUBLE NOT NULL,
      heating_oil_close DOUBLE NOT NULL,
      crack_spread DOUBLE NOT NULL,
      ai_json JSON DEFAULT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real weekly EIA Petroleum Status Report figures (crude/gasoline/
  // distillate stocks + week-over-week change) plus Claude's cached
  // reaction read — see src/eiaInventory.js. One row per report date.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS eia_inventory_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      report_date DATE NOT NULL UNIQUE,
      crude_stocks_kbbl DOUBLE NOT NULL,
      gasoline_stocks_kbbl DOUBLE NOT NULL,
      distillate_stocks_kbbl DOUBLE NOT NULL,
      crude_change_kbbl DOUBLE NOT NULL,
      gasoline_change_kbbl DOUBLE NOT NULL,
      distillate_change_kbbl DOUBLE NOT NULL,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real weekly EIA Natural Gas Storage Report figures (working gas in
  // storage, vs-last-year and vs-5yr-average deviations) plus Claude's
  // cached reaction read — see src/ngStorage.js. One row per report date.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ng_storage_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      report_date DATE NOT NULL UNIQUE,
      storage_bcf DOUBLE NOT NULL,
      weekly_change_bcf DOUBLE NOT NULL,
      vs_last_year_pct DOUBLE NOT NULL,
      vs_5y_avg_pct DOUBLE NOT NULL,
      season ENUM('INJECTION_SEASON','WITHDRAWAL_SEASON') NOT NULL,
      ai_json JSON,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per referred user who has ever converted to a paid plan —
  // unique on referred_user_id so a webhook retry or a later
  // upgrade/downgrade/re-upgrade can never credit the same referral twice
  // (see src/referrals.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS referral_credits (
      id INT AUTO_INCREMENT PRIMARY KEY,
      referrer_id INT NOT NULL,
      referred_user_id INT NOT NULL,
      amount_cents INT NOT NULL,
      stripe_balance_transaction_id VARCHAR(255) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_referred_user (referred_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily FX close per currency pair (Alpha Vantage FX_DAILY), for the
  // Forex Terminal — see src/forex.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS forex_rates_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      pair VARCHAR(8) NOT NULL,
      bar_date DATE NOT NULL,
      rate DOUBLE NOT NULL,
      UNIQUE KEY uniq_pair_date (pair, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Shared FRED (St. Louis Fed) time series cache — one row per series per
  // observation date. Backs both the Treasury yield curve (DGS3MO..DGS30,
  // see src/yieldCurve.js) and the macro indicators panel (CPI, GDP,
  // UNRATE, FEDFUNDS, etc, see src/economicIndicators.js) since both are
  // just different FRED series IDs read the same way.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS fred_series_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      series_id VARCHAR(16) NOT NULL,
      obs_date DATE NOT NULL,
      value DOUBLE NOT NULL,
      UNIQUE KEY uniq_series_date (series_id, obs_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // News Terminal — parsed RSS headlines from Reuters/USDA/AgWeb/DTN/WSJ/FT,
  // one row per unique link, with CullyAI's grain/energy/macro tag filled in
  // lazily as new headlines come in — see src/newsTerminal.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS news_headlines (
      id INT AUTO_INCREMENT PRIMARY KEY,
      source VARCHAR(64) NOT NULL,
      title VARCHAR(512) NOT NULL,
      link VARCHAR(512) NOT NULL,
      published_at DATETIME NOT NULL,
      tag VARCHAR(16) DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_link (link)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Single-row cache of the last sector-ETF performance snapshot (XLE, MOO,
  // XLK, XLF, XLI, XLP, GLD, SLV, USO, UNG via Yahoo Finance) — see
  // src/sectorHeatmap.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sector_heatmap_cache (
      id INT PRIMARY KEY DEFAULT 1,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Single-row cache of the last CoinGecko top-10 markets snapshot
  // (keyless API, but rate-limited) — see src/crypto.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS crypto_snapshot_cache (
      id INT PRIMARY KEY DEFAULT 1,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Single-row cache of the upcoming-earnings window from Financial
  // Modeling Prep, filtered to agribusiness tickers — see
  // src/earningsCalendar.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS earnings_calendar_cache (
      id INT PRIMARY KEY DEFAULT 1,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Single-row cache of the upcoming high-impact macro event window from
  // Financial Modeling Prep — see src/economicCalendar.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS economic_calendar_cache (
      id INT PRIMARY KEY DEFAULT 1,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // CullyAI conversation memory — every chat turn, so the assistant can
  // recall what a user asked previously across sessions (see
  // src/cullyaiMemory.js). Kept separate from cullyai_usage (which only
  // counts messages for the daily cap).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cullyai_messages (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      role ENUM('user','assistant') NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_user_created (user_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per user: the commodities/topics CullyAI has seen them ask
  // about, so a "welcome back" nudge can reference real prior context
  // instead of guessing — see src/cullyaiMemory.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cullyai_user_context (
      user_id INT PRIMARY KEY,
      last_commodities JSON,
      last_topics JSON,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per day: CullyAI's proactive cross-asset synthesis (dollar,
  // crude, yield curve, WASDE) — see src/crossAssetSynthesis.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cross_asset_synthesis (
      id INT PRIMARY KEY DEFAULT 1,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per day: the 3 proactive insights CullyAI surfaces on the
  // Dashboard without being asked — see src/proactiveInsights.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS daily_insights (
      insight_date DATE PRIMARY KEY,
      ai_json JSON NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per user-logged decision against a CullyAI recommendation —
  // the Audit Trail / Decision Log (see src/decisionLog.js). price_at_log
  // is the futures/basis price when logged; outcome fields are filled in
  // as time passes, mirroring wasde_surprises' reaction-tracking pattern.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS decision_log (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      cullyai_context TEXT,
      user_note TEXT NOT NULL,
      price_at_log DOUBLE NULL,
      price_7d DOUBLE NULL,
      price_30d DOUBLE NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_user_created (user_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Named, per-user saved dashboard layouts — which widgets are visible
  // and in what order (see src/customDashboards.js). Layout itself is a
  // simple ordered widget-id list, not a pixel-perfect grid.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS custom_dashboards (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      name VARCHAR(64) NOT NULL,
      widget_ids JSON NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_user_name (user_id, name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Community Insights Feed — short user-submitted market notes,
  // CullyAI-fact-checked against real cached data before being shown (see
  // src/communityInsights.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS community_insights (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      commodity VARCHAR(16) NOT NULL,
      body VARCHAR(500) NOT NULL,
      fact_check TEXT,
      fact_check_verdict ENUM('CONSISTENT','QUESTIONABLE','UNVERIFIED') DEFAULT 'UNVERIFIED',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Croploo Learn articles — short CullyAI-written explainers illustrated
  // with real current data (see src/croplooLearn.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS learn_articles (
      id INT AUTO_INCREMENT PRIMARY KEY,
      slug VARCHAR(128) NOT NULL UNIQUE,
      title VARCHAR(255) NOT NULL,
      body TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Croploo Signals weekly newsletter — free email signups (no Croploo
  // account required) plus the generated weekly digests archive (see
  // src/newsletter.js).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS newsletter_subscribers (
      id INT AUTO_INCREMENT PRIMARY KEY,
      email VARCHAR(255) NOT NULL UNIQUE,
      confirmed BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS newsletter_issues (
      id INT AUTO_INCREMENT PRIMARY KEY,
      issue_date DATE NOT NULL UNIQUE,
      ai_json JSON NOT NULL,
      sent_at DATETIME NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Public profile settings — which commodities a user has opted to show
  // on their public croploo.app/u/<username> page, and which of their
  // community insights are pinned there (see src/publicProfiles.js). No
  // public web frontend exists in this repo yet — this is the backend
  // data model + API only; see the newsletter/public-profile note in the
  // implementation summary.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public_profiles (
      user_id INT PRIMARY KEY,
      username VARCHAR(32) NOT NULL UNIQUE,
      is_public BOOLEAN NOT NULL DEFAULT FALSE,
      tracked_commodities JSON,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Generic named-spread daily history (currently WTI-Brent; a reusable
  // slot for future spreads that need their own fetched series rather
  // than being computable from tables that already exist) — see
  // src/spreadTerminal.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS spread_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      spread_key VARCHAR(32) NOT NULL,
      bar_date DATE NOT NULL,
      value DOUBLE NOT NULL,
      UNIQUE KEY uniq_spread_date (spread_key, bar_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per WASDE-equivalent NASS release per commodity: how far the
  // new number deviated from the prior one, plus the real futures-price
  // reaction at 24h/48h/1 week after release (filled in as time passes —
  // see src/wasdeSurprises.js). Lets the app compare a fresh surprise
  // against the most similar one in its own real history instead of a
  // hardcoded "like April 2021" example.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS wasde_surprises (
      id INT AUTO_INCREMENT PRIMARY KEY,
      commodity VARCHAR(16) NOT NULL,
      release_date DATE NOT NULL,
      metric VARCHAR(32) NOT NULL,
      previous_value DOUBLE NOT NULL,
      current_value DOUBLE NOT NULL,
      surprise_pct DOUBLE NOT NULL,
      price_at_release DOUBLE NULL,
      price_24h DOUBLE NULL,
      price_48h DOUBLE NULL,
      price_1w DOUBLE NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_commodity_release (commodity, release_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // ── Team Accounts ─────────────────────────────────────────────────────────
  // One row per team. owner_id is the admin who created and pays for the team.
  // seat_count is the number of member slots purchased (including the admin).
  // stripe_subscription_id is set once the Stripe checkout completes.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS teams (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(120) NOT NULL,
      owner_id INT NOT NULL,
      plan_tier VARCHAR(16) NOT NULL,
      seat_count INT NOT NULL DEFAULT 5,
      stripe_customer_id VARCHAR(255) DEFAULT NULL,
      stripe_subscription_id VARCHAR(255) DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // One row per pending or accepted invitation. email is NULL for open
  // link invites (anyone with the token can join). accepted_at is set when
  // a user registers or logs in with the token.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS team_invitations (
      id INT AUTO_INCREMENT PRIMARY KEY,
      team_id INT NOT NULL,
      email VARCHAR(255) DEFAULT NULL,
      invite_token VARCHAR(64) NOT NULL UNIQUE,
      accepted_at DATETIME DEFAULT NULL,
      expires_at DATETIME NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_team (team_id),
      INDEX idx_token (invite_token)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // ── Public API Keys ─────────────────────────────────────────────────────
  // API keys for external data access (Quant Funds, Prop Desks, Agribusiness IT).
  // Each user can have multiple keys with different scopes/limits.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS api_keys (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      key_hash VARCHAR(64) NOT NULL UNIQUE,
      key_prefix VARCHAR(8) NOT NULL,
      name VARCHAR(120) NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      last_used_at DATETIME NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_user (user_id),
      INDEX idx_prefix (key_prefix)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Daily API call tracking per key for rate limiting.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS api_usage (
      id INT AUTO_INCREMENT PRIMARY KEY,
      key_id INT NOT NULL,
      call_date DATE NOT NULL,
      call_count INT DEFAULT 0,
      UNIQUE KEY uniq_key_date (key_id, call_date),
      INDEX idx_date (call_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Single-row-per-symbol cache of today's 15-minute intraday bars
  // (Yahoo Finance, keyless) — see src/intradayFutures.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS intraday_futures_cache (
      symbol VARCHAR(8) PRIMARY KEY,
      payload JSON NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // World-total weekly USDA FAS Export Sales, aggregated server-side
  // (SoQL sum()) across all destination countries — see
  // src/exportSales.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS export_sales_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      snapshot_date DATE NOT NULL,
      marketing_year VARCHAR(9) NOT NULL,
      weekly_exports BIGINT NOT NULL,
      net_sales BIGINT NOT NULL,
      accumulated_exports BIGINT NOT NULL,
      outstanding_sales BIGINT NOT NULL,
      total_commitments BIGINT NOT NULL,
      UNIQUE KEY uniq_symbol_date (symbol, snapshot_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Top destination countries for the latest reported week per
  // commodity — replaced wholesale on each refresh rather than
  // accumulated, since only the current week's leaderboard matters.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS export_sales_destinations (
      id INT AUTO_INCREMENT PRIMARY KEY,
      symbol VARCHAR(8) NOT NULL,
      snapshot_date DATE NOT NULL,
      country VARCHAR(64) NOT NULL,
      weekly_exports BIGINT NOT NULL,
      net_sales BIGINT NOT NULL,
      outstanding_sales BIGINT NOT NULL,
      rank_order INT NOT NULL,
      UNIQUE KEY uniq_symbol_date_country (symbol, snapshot_date, country)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real weekly grain rail car loadings by state (STB Rail Service
  // Metrics via USDA AgTransport) — see src/grainRailCars.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS rail_car_loadings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      state VARCHAR(4) NOT NULL,
      week_date DATE NOT NULL,
      total_cars INT NOT NULL,
      shuttle_cars INT NOT NULL,
      UNIQUE KEY uniq_state_week (state, week_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real Mississippi River stage/flow readings (NOAA NWPS) — see
  // src/mississippiGauges.js. One downsampled reading per gauge per day.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS mississippi_gauge_readings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      lid VARCHAR(16) NOT NULL,
      reading_date DATE NOT NULL,
      stage_ft DECIMAL(8,2) NOT NULL,
      flow_kcfs DECIMAL(10,2) NOT NULL,
      UNIQUE KEY uniq_lid_date (lid, reading_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  // Real US Drought Monitor D0–D4 severity percentages per state — see
  // src/droughtMonitor.js.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS drought_monitor_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      state VARCHAR(4) NOT NULL,
      map_date DATE NOT NULL,
      none_pct DECIMAL(5,1) NOT NULL,
      d0_pct DECIMAL(5,1) NOT NULL,
      d1_pct DECIMAL(5,1) NOT NULL,
      d2_pct DECIMAL(5,1) NOT NULL,
      d3_pct DECIMAL(5,1) NOT NULL,
      d4_pct DECIMAL(5,1) NOT NULL,
      any_drought_pct DECIMAL(5,1) NOT NULL,
      UNIQUE KEY uniq_state_date (state, map_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
}
