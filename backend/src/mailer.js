import nodemailer from "nodemailer";

import * as config from "./config.js";

let transporter = null;

function getTransporter() {
  if (!config.SMTP_HOST) return null;
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: config.SMTP_HOST,
      port: config.SMTP_PORT,
      secure: config.SMTP_PORT === 465,
      auth: { user: config.SMTP_USER, pass: config.SMTP_PASS },
    });
  }
  return transporter;
}

function briefEmailHtml(brief) {
  const list = (items) => items.map((i) => `<li>${i}</li>`).join("");
  return `
    <div style="font-family:-apple-system,Segoe UI,sans-serif;max-width:560px">
      <h2 style="margin:0 0 4px">Croploo Morning Brief</h2>
      <p style="color:#8a8a8a;margin:0 0 20px">${brief.date}</p>
      <p style="font-size:15px;line-height:1.5">${brief.summary}</p>
      <h3 style="font-size:13px;letter-spacing:1px;color:#8a8a8a;margin-top:24px">TOP OPPORTUNITIES</h3>
      <ul style="padding-left:18px;margin:8px 0">${list(brief.top_opportunities)}</ul>
      <h3 style="font-size:13px;letter-spacing:1px;color:#8a8a8a;margin-top:16px">RISK FACTORS</h3>
      <ul style="padding-left:18px;margin:8px 0">${list(brief.risk_factors)}</ul>
      <h3 style="font-size:13px;letter-spacing:1px;color:#8a8a8a;margin-top:16px">THIS WEEK</h3>
      <ul style="padding-left:18px;margin:8px 0">${list(brief.key_events_this_week)}</ul>
      <p style="color:#8a8a8a;font-size:12px;margin-top:24px">
        Open Croploo for the full picture, or turn this off in Settings → Notifications.
      </p>
    </div>`;
}

/** One recipient's morning brief email — real SMTP send via Mailgun, or a
 * dev-mode console log fallback (same pattern as sendVerificationEmail). */
export async function sendDailyBriefEmail(to, brief) {
  const t = getTransporter();
  if (!t) {
    console.log(`[dev] daily brief email for ${to}: ${brief.summary}`);
    return;
  }
  try {
    await t.sendMail({
      from: config.MAIL_FROM,
      to,
      subject: `Croploo Morning Brief — ${brief.date}`,
      text: `${brief.summary}\n\nTop opportunities:\n${brief.top_opportunities.join("\n")}\n\nRisk factors:\n${brief.risk_factors.join("\n")}`,
      html: briefEmailHtml(brief),
    });
  } catch (err) {
    console.error(`Failed to send daily brief email to ${to}:`, err.message);
  }
}

function newsletterEmailHtml(issue) {
  const list = (items) => items.map((i) => `<li>${i}</li>`).join("");
  return `
    <div style="font-family:-apple-system,Segoe UI,sans-serif;max-width:560px">
      <h2 style="margin:0 0 4px">Croploo Signals</h2>
      <p style="color:#8a8a8a;margin:0 0 20px">Week of ${issue.issue_date}</p>
      <h3 style="font-size:13px;letter-spacing:1px;color:#8a8a8a">THIS WEEK'S 5 SIGNALS</h3>
      <ol style="padding-left:18px;margin:8px 0;font-size:14px;line-height:1.6">${list(issue.signals)}</ol>
      <p style="color:#8a8a8a;font-size:12px;margin-top:24px">
        Free weekly newsletter from Croploo. Unsubscribe by replying "unsubscribe".
      </p>
    </div>`;
}

/** One recipient's weekly Croploo Signals digest — see newsletter.js. */
export async function sendNewsletterEmail(to, issue) {
  const t = getTransporter();
  if (!t) {
    console.log(`[dev] newsletter email for ${to}: ${issue.signals.join(" | ")}`);
    return;
  }
  try {
    await t.sendMail({
      from: config.MAIL_FROM,
      to,
      subject: `Croploo Signals — Week of ${issue.issue_date}`,
      text: issue.signals.join("\n"),
      html: newsletterEmailHtml(issue),
    });
  } catch (err) {
    console.error(`Failed to send newsletter email to ${to}:`, err.message);
  }
}

export async function sendPasswordResetEmail(to, code) {
  const t = getTransporter();
  if (!t) {
    console.log(`[dev] password reset code for ${to}: ${code}`);
    return;
  }
  try {
    await t.sendMail({
      from: config.MAIL_FROM,
      to,
      subject: "Reset your Croploo password",
      text: `Your Croploo password reset code is ${code}. It expires in ${config.VERIFICATION_CODE_TTL_MINUTES} minutes. If you didn't request this, you can ignore this email.`,
      html: `<p>Your Croploo password reset code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p><p>It expires in ${config.VERIFICATION_CODE_TTL_MINUTES} minutes. If you didn't request this, you can ignore this email.</p>`,
    });
  } catch (err) {
    console.error(`Failed to send password reset email to ${to}:`, err.message);
    console.log(`[dev] password reset code for ${to}: ${code}`);
  }
}

export async function sendVerificationEmail(to, code) {
  const t = getTransporter();
  if (!t) {
    // No SMTP configured — fall back to logging so the flow stays testable.
    console.log(`[dev] verification code for ${to}: ${code}`);
    return;
  }
  try {
    await t.sendMail({
      from: config.MAIL_FROM,
      to,
      subject: "Your Croploo verification code",
      text: `Your Croploo verification code is ${code}. It expires in ${config.VERIFICATION_CODE_TTL_MINUTES} minutes.`,
      html: `<p>Your Croploo verification code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p><p>It expires in ${config.VERIFICATION_CODE_TTL_MINUTES} minutes.</p>`,
    });
  } catch (err) {
    // Don't let a broken SMTP config break registration/login — the code
    // is already stored, so at minimum log it so the flow stays testable.
    console.error(`Failed to send verification email to ${to}:`, err.message);
    console.log(`[dev] verification code for ${to}: ${code}`);
  }
}
