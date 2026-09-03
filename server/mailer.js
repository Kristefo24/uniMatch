// Thin wrapper around nodemailer + Gmail SMTP. If GMAIL_USER/GMAIL_APP_PASSWORD
// aren't set (local dev without the credential, or a misconfigured deploy),
// this logs the email to the console instead of throwing -- lets the whole
// OTP flow be developed and tested end-to-end without ever needing real
// credentials or sending real mail.
const nodemailer = require('nodemailer');

let transporter = null;
function getTransporter() {
  if (transporter) return transporter;
  if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) return null;
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user: process.env.GMAIL_USER, pass: process.env.GMAIL_APP_PASSWORD },
  });
  return transporter;
}

// Shared wrapper so every outgoing email looks consistent -- no external
// assets/images (many mail clients block remote images by default) and
// inline styles only (many clients strip <style> blocks), so this renders
// the same in Gmail, Outlook, etc. `bodyHtml` is the message-specific content.
function emailTemplate(bodyHtml) {
  return `<div style="font-family: Arial, Helvetica, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; color: #1a1a1a;">
    <div style="font-size: 18px; font-weight: 700; color: #1f6d3f; margin-bottom: 16px;">UniMatch Gasabo</div>
    <div style="font-size: 15px; line-height: 1.6;">${bodyHtml}</div>
    <div style="margin-top: 28px; font-size: 12px; color: #888;">This is an automated message — please don't reply to this email.</div>
  </div>`;
}

// Used by all 3 OTP-carrying emails (signup verification, resend-signup-otp,
// forgot-password) -- wraps the 6-digit code in bold, larger styling so it's
// unmistakable at a glance. Doesn't change what the plain-text fallback says.
function otpEmailHtml({ intro, otp, ttlMinutes = 2 }) {
  return emailTemplate(`
    <p>${intro}</p>
    <p style="text-align:center; margin:24px 0;">
      <span style="display:inline-block; font-size:28px; font-weight:700; letter-spacing:6px; color:#1f6d3f; background:#eef7f0; padding:12px 20px; border-radius:8px;">${otp}</span>
    </p>
    <p>This code expires in ${ttlMinutes} minute${ttlMinutes === 1 ? '' : 's'}.</p>`);
}

async function sendMail({ to, subject, text, html }) {
  const t = getTransporter();
  if (!t) {
    console.log(`[mailer] GMAIL_USER/GMAIL_APP_PASSWORD not set -- logging instead of sending.\n  To: ${to}\n  Subject: ${subject}\n  Body: ${text}${html ? '\n  (HTML body also set — not shown in this log)' : ''}`);
    return { sent: false, logged: true };
  }
  await t.sendMail({ from: `UniMatch Gasabo <${process.env.GMAIL_USER}>`, to, subject, text, html });
  return { sent: true };
}

module.exports = { sendMail, emailTemplate, otpEmailHtml };
