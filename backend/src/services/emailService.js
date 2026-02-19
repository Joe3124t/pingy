const nodemailer = require('nodemailer');
const { env, isProduction } = require('../config/env');
const { HttpError } = require('../utils/httpError');

let transporter = null;

const hasSmtpConfig = () =>
  Boolean(env.SMTP_HOST && env.SMTP_PORT && env.SMTP_USER && env.SMTP_PASS && env.SMTP_FROM_EMAIL);
const hasResendConfig = () => Boolean(env.RESEND_API_KEY && env.RESEND_FROM_EMAIL);
const hasBrevoConfig = () => Boolean(env.BREVO_API_KEY && env.BREVO_FROM_EMAIL);
const hasRelayConfig = () => Boolean(env.EMAIL_RELAY_URL && env.EMAIL_RELAY_TOKEN);
const hasFormSubmitConfig = () => Boolean(env.FORMSUBMIT_INBOX_EMAIL);
const hasEmailConfig = () =>
  hasResendConfig() || hasBrevoConfig() || hasRelayConfig() || hasFormSubmitConfig() || hasSmtpConfig();

const getTransporter = () => {
  if (!hasSmtpConfig()) {
    return null;
  }

  if (transporter) {
    return transporter;
  }

  transporter = nodemailer.createTransport({
    host: env.SMTP_HOST,
    port: env.SMTP_PORT,
    secure: Boolean(env.SMTP_SECURE),
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 30000,
    tls: {
      servername: env.SMTP_TLS_SERVERNAME || env.SMTP_HOST,
    },
    auth: {
      user: env.SMTP_USER,
      pass: env.SMTP_PASS,
    },
  });

  return transporter;
};

const buildResetPasswordEmail = ({ username, code, expiresInMinutes }) => {
  const safeName = username || 'there';

  return {
    subject: 'Pingy password reset code',
    text: [
      `Hi ${safeName},`,
      '',
      `Your Pingy password reset code is: ${code}`,
      `This code expires in ${expiresInMinutes} minutes.`,
      '',
      'If you did not request this, ignore this email.',
    ].join('\n'),
    html: `
      <div style="font-family:Arial,sans-serif;line-height:1.6;color:#0f172a;max-width:560px;margin:0 auto;">
        <h2 style="margin:0 0 12px;">Pingy Password Reset</h2>
        <p style="margin:0 0 12px;">Hi ${safeName},</p>
        <p style="margin:0 0 12px;">Use this code to reset your password:</p>
        <p style="margin:0 0 16px; font-size:28px; font-weight:700; letter-spacing:4px; color:#0e7490;">${code}</p>
        <p style="margin:0 0 12px;">This code expires in ${expiresInMinutes} minutes.</p>
        <p style="margin:0; color:#475569;">If you did not request this, you can safely ignore this email.</p>
      </div>
    `,
  };
};

const readResponseText = async (response) => {
  try {
    return await response.text();
  } catch (_) {
    return '';
  }
};

const sendWithResend = async ({ toEmail, message }) => {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: `"${env.RESEND_FROM_NAME}" <${env.RESEND_FROM_EMAIL}>`,
      to: [toEmail],
      subject: message.subject,
      text: message.text,
      html: message.html,
    }),
  });

  if (!response.ok) {
    const body = await readResponseText(response);
    throw new Error(`Resend request failed (${response.status}): ${body}`);
  }
};

const sendWithBrevo = async ({ toEmail, username, message }) => {
  const response = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': env.BREVO_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      sender: {
        name: env.BREVO_FROM_NAME,
        email: env.BREVO_FROM_EMAIL,
      },
      to: [{ email: toEmail, name: username || undefined }],
      subject: message.subject,
      textContent: message.text,
      htmlContent: message.html,
    }),
  });

  if (!response.ok) {
    const body = await readResponseText(response);
    throw new Error(`Brevo request failed (${response.status}): ${body}`);
  }
};

const sendWithRelay = async ({ toEmail, message }) => {
  const response = await fetch(env.EMAIL_RELAY_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.EMAIL_RELAY_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: toEmail,
      subject: message.subject,
      text: message.text,
    }),
  });

  if (!response.ok) {
    const body = await readResponseText(response);
    throw new Error(`Relay request failed (${response.status}): ${body}`);
  }
};

const sendWithFormSubmit = async ({ toEmail, message }) => {
  if (String(toEmail).toLowerCase() !== String(env.FORMSUBMIT_INBOX_EMAIL).toLowerCase()) {
    throw new HttpError(
      503,
      'Password reset for this email is temporarily unavailable. Contact support for manual reset.',
    );
  }

  const params = new URLSearchParams();
  params.set('name', env.FORMSUBMIT_FROM_NAME || 'Pingy Messenger');
  params.set('email', env.FORMSUBMIT_INBOX_EMAIL);
  params.set('_subject', message.subject);
  params.set('_template', 'table');
  params.set('_captcha', 'false');
  params.set('message', message.text);

  const response = await fetch(`https://formsubmit.co/ajax/${encodeURIComponent(env.FORMSUBMIT_INBOX_EMAIL)}`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      Origin: env.CORS_ORIGIN.split(',')[0].trim(),
      Referer: `${env.CORS_ORIGIN.split(',')[0].trim()}/`,
    },
    body: params.toString(),
  });

  const bodyText = await readResponseText(response);
  let bodyJson = null;
  if (bodyText) {
    try {
      bodyJson = JSON.parse(bodyText);
    } catch (_) {
      bodyJson = null;
    }
  }

  if (!response.ok || (bodyJson && String(bodyJson.success) !== 'true')) {
    const maybeMessage = bodyJson?.message || bodyText || 'Unable to send email';
    if (String(maybeMessage).toLowerCase().includes('activation')) {
      throw new HttpError(
        503,
        'Email sending is not activated yet. Check inbox for the activation email and click Activate Form once.',
      );
    }

    throw new Error(`FormSubmit request failed (${response.status}): ${maybeMessage}`);
  }
};

const sendPasswordResetCodeEmail = async ({ toEmail, username, code, expiresInMinutes }) => {
  const message = buildResetPasswordEmail({ username, code, expiresInMinutes });

  if (hasResendConfig()) {
    await sendWithResend({ toEmail, message });
    return;
  }

  if (hasBrevoConfig()) {
    await sendWithBrevo({ toEmail, username, message });
    return;
  }

  if (hasRelayConfig()) {
    await sendWithRelay({ toEmail, message });
    return;
  }

  if (hasFormSubmitConfig()) {
    await sendWithFormSubmit({ toEmail, message });
    return;
  }

  const client = getTransporter();

  if (!client) {
    if (isProduction) {
      throw new HttpError(503, 'Email service is not configured');
    }

    console.log(`[DEV] Password reset code for ${toEmail}: ${code}`);
    return;
  }

  await client.sendMail({
    from: `"${env.SMTP_FROM_NAME}" <${env.SMTP_FROM_EMAIL}>`,
    to: toEmail,
    subject: message.subject,
    text: message.text,
    html: message.html,
  });
};

module.exports = {
  hasEmailConfig,
  hasSmtpConfig,
  sendPasswordResetCodeEmail,
};
