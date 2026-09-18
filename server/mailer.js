// Sends transactional email via Brevo's HTTP API rather than raw SMTP.
// Railway's outbound network was confirmed (VERIFY FAILED: Connection
// timeout, tested directly from the running container) to be unable to
// reach Gmail's SMTP servers -- likely blocked at the network/IP level,
// a common restriction on shared cloud hosting. An HTTPS API call on
// port 443 isn't subject to that. If BREVO_API_KEY or GMAIL_USER (reused
// as the verified "from" address -- no domain needed, just a
// single-sender verification in Brevo) aren't set, this logs the email
// to the console instead of sending -- lets the whole OTP flow be
// developed/tested end-to-end without real credentials or sending real
// mail.
const BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';

function configured() {
  return !!(process.env.BREVO_API_KEY && process.env.GMAIL_USER);
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

/// Told to the graduate, not just recorded against them: the reason they were
/// suspended, and what signing in will involve from now on. Being locked out
/// with no explanation is the version of this that generates support requests.
function suspensionEmailHtml({ suspended, reason }) {
  if (!suspended) {
    return emailTemplate(`
      <p>Your UniMatch account is active again.</p>
      <p>You can sign in as normal — no verification code is needed.</p>`);
  }
  return emailTemplate(`
    <p>Your UniMatch account has been <strong>suspended</strong>.</p>
    ${reason ? `<p style="margin:20px 0; padding:12px 16px; background:#fdf3ec; border-left:3px solid #c25a1f; border-radius:4px;">
      <strong>Reason:</strong> ${reason}</p>` : ''}
    <p>You can still sign in with your usual email and password, but you will be asked to
       verify your email first: we send a 6-digit code to this address each time, and you
       enter it on the <strong>Verify your email</strong> screen.</p>
    <p style="color:#6b6960; font-size:13px;">Contact the UniMatch administrator if you think this is a mistake.</p>`);
}

async function sendMail({ to, subject, text, html }) {
  if (!configured()) {
    console.log(`[mailer] BREVO_API_KEY/GMAIL_USER not set -- logging instead of sending.\n  To: ${to}\n  Subject: ${subject}\n  Body: ${text}${html ? '\n  (HTML body also set — not shown in this log)' : ''}`);
    return { sent: false, logged: true };
  }
  const res = await fetch(BREVO_API_URL, {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({
      sender: { name: 'UniMatch Gasabo', email: process.env.GMAIL_USER },
      to: [{ email: to }],
      subject,
      textContent: text,
      htmlContent: html || `<pre>${text}</pre>`,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Brevo send failed (${res.status}): ${body}`);
  }
  return { sent: true };
}

module.exports = { sendMail, emailTemplate, otpEmailHtml, suspensionEmailHtml };
