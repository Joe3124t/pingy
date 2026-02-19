import { connect } from 'cloudflare:sockets';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });

const sanitizeHeader = (value) => String(value || '').replace(/[\r\n]+/g, ' ').trim();

const normalizeBody = (value) =>
  String(value || '')
    .replace(/\r?\n/g, '\r\n')
    .replace(/^\./gm, '..');

const readSmtpResponse = async (reader, state) => {
  while (true) {
    const { value, done } = await reader.read();

    if (done) {
      throw new Error('SMTP connection closed unexpectedly');
    }

    state.buffer += decoder.decode(value, { stream: true });

    const lines = state.buffer.split(/\r\n/);
    state.buffer = lines.pop() || '';

    for (const line of lines) {
      if (!line) {
        continue;
      }

      state.lastLine = line;

      if (/^\d{3} /.test(line)) {
        return {
          code: Number(line.slice(0, 3)),
          line,
        };
      }
    }
  }
};

const expectSmtp = async (reader, state, expectedCodes) => {
  const response = await readSmtpResponse(reader, state);

  if (!expectedCodes.includes(response.code)) {
    throw new Error(`SMTP error: ${response.line}`);
  }

  return response;
};

const writeSmtp = async (writer, command) => {
  await writer.write(encoder.encode(`${command}\r\n`));
};

const smtpSend = async ({ env, to, subject, text }) => {
  const host = env.GMAIL_SMTP_HOST || 'smtp.gmail.com';
  const port = Number(env.GMAIL_SMTP_PORT || 465);

  const socket = connect(
    {
      hostname: host,
      port,
    },
    {
      secureTransport: 'on',
    },
  );

  const reader = socket.readable.getReader();
  const writer = socket.writable.getWriter();
  const state = {
    buffer: '',
    lastLine: '',
  };

  try {
    await expectSmtp(reader, state, [220]);

    await writeSmtp(writer, 'EHLO pingy-relay');
    await expectSmtp(reader, state, [250]);

    await writeSmtp(writer, 'AUTH LOGIN');
    await expectSmtp(reader, state, [334]);

    await writeSmtp(writer, btoa(String(env.GMAIL_USER)));
    await expectSmtp(reader, state, [334]);

    await writeSmtp(writer, btoa(String(env.GMAIL_APP_PASSWORD)));
    await expectSmtp(reader, state, [235]);

    await writeSmtp(writer, `MAIL FROM:<${env.GMAIL_USER}>`);
    await expectSmtp(reader, state, [250]);

    await writeSmtp(writer, `RCPT TO:<${to}>`);
    await expectSmtp(reader, state, [250, 251]);

    await writeSmtp(writer, 'DATA');
    await expectSmtp(reader, state, [354]);

    const date = new Date().toUTCString();
    const safeSubject = sanitizeHeader(subject || 'Pingy Message');
    const bodyText = normalizeBody(text || '');

    const payload = [
      `From: Pingy Messenger <${env.GMAIL_USER}>`,
      `To: <${to}>`,
      `Subject: ${safeSubject}`,
      `Date: ${date}`,
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      bodyText,
      '',
      '.',
      '',
    ].join('\r\n');

    await writer.write(encoder.encode(payload));
    await expectSmtp(reader, state, [250]);

    await writeSmtp(writer, 'QUIT');
    await expectSmtp(reader, state, [221]);
  } finally {
    try {
      writer.releaseLock();
    } catch (_) {}
    try {
      reader.releaseLock();
    } catch (_) {}
    try {
      socket.close();
    } catch (_) {}
  }
};

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return json({ message: 'Method not allowed' }, 405);
    }

    const token = request.headers.get('authorization') || '';

    if (!env.RELAY_TOKEN || token !== `Bearer ${env.RELAY_TOKEN}`) {
      return json({ message: 'Unauthorized' }, 401);
    }

    if (!env.GMAIL_USER || !env.GMAIL_APP_PASSWORD) {
      return json({ message: 'Relay is not configured' }, 503);
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json({ message: 'Invalid JSON body' }, 400);
    }

    const to = String(body?.to || '').trim();
    const subject = String(body?.subject || '').trim();
    const text = String(body?.text || '').trim();

    if (!to || !subject || !text) {
      return json({ message: 'to, subject and text are required' }, 400);
    }

    try {
      await smtpSend({ env, to, subject, text });
      return json({ ok: true });
    } catch (error) {
      return json({ message: 'SMTP relay failed', error: String(error?.message || error) }, 502);
    }
  },
};
