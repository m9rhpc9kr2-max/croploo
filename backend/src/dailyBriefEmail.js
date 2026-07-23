/**
 * Fans the morning brief out as email so a user who hasn't opened the
 * app in weeks still gets pulled back in — meant to be triggered once a
 * day at 7:30 ET by an external scheduler (Cloud Scheduler; Cloud Run
 * itself has no cron runner) hitting POST /v1/daily-brief/send-now with
 * the X-Cron-Secret header (see routes/dailyBrief.js and config.CRON_SECRET).
 *
 * Real push notifications (mobile/desktop OS-level) aren't wired up here
 * — that needs a push provider (FCM/APNs) and per-platform client setup
 * this repo doesn't have yet, so this intentionally only covers email,
 * which is real end-to-end via Mailgun/mailer.js.
 */
import { pool } from "./db.js";
import * as dailyBrief from "./dailyBrief.js";
import { sendDailyBriefEmail } from "./mailer.js";

export async function sendToAllSubscribers() {
  const [users] = await pool.query(
    "SELECT id, email FROM users WHERE is_verified = TRUE AND daily_brief_email = TRUE"
  );

  let sent = 0;
  for (const user of users) {
    try {
      const row = await dailyBrief.ensureForUser(user.id);
      await sendDailyBriefEmail(user.email, dailyBrief.serialize(row));
      sent += 1;
    } catch (err) {
      console.error(`Daily brief email failed for user ${user.id}:`, err);
    }
  }
  return { recipients: users.length, sent };
}
