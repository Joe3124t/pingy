const IDENTITY_PREFIX = 'pingy.e2ee.identity.v1.';
const DEVICE_SECRET_KEY = 'pingy.e2ee.device-secret.v1';
const WRAP_ITERATIONS = 210_000;

const privateKeyCache = new Map();
const sharedKeyCache = new Map();

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const assertWebCrypto = () => {
  if (!window.crypto?.subtle) {
    throw new Error('WebCrypto is not available in this browser');
  }
};

const bytesToBase64 = (bytes) => {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = '';

  for (let index = 0; index < view.length; index += 1) {
    binary += String.fromCharCode(view[index]);
  }

  return window.btoa(binary);
};

const base64ToBytes = (value) => {
  const binary = window.atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
};

const randomBytes = (size) => window.crypto.getRandomValues(new Uint8Array(size));

const getOrCreateDeviceSecret = () => {
  const existing = window.localStorage.getItem(DEVICE_SECRET_KEY);

  if (existing) {
    return existing;
  }

  const created = bytesToBase64(randomBytes(32));
  window.localStorage.setItem(DEVICE_SECRET_KEY, created);
  return created;
};

const deriveWrappingKey = async (secret, saltBytes) => {
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw',
    textEncoder.encode(secret),
    { name: 'PBKDF2' },
    false,
    ['deriveKey'],
  );

  return window.crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBytes,
      iterations: WRAP_ITERATIONS,
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
};

const encryptPrivateKeyPayload = async ({ payload, secret }) => {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const wrappingKey = await deriveWrappingKey(secret, salt);
  const encodedPayload = textEncoder.encode(JSON.stringify(payload));

  const encrypted = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
    },
    wrappingKey,
    encodedPayload,
  );

  return {
    salt: bytesToBase64(salt),
    iv: bytesToBase64(iv),
    ciphertext: bytesToBase64(new Uint8Array(encrypted)),
    iterations: WRAP_ITERATIONS,
  };
};

const decryptPrivateKeyPayload = async ({ envelope, secret }) => {
  const salt = base64ToBytes(envelope.salt);
  const iv = base64ToBytes(envelope.iv);
  const wrappingKey = await deriveWrappingKey(secret, salt);
  const encryptedBytes = base64ToBytes(envelope.ciphertext);

  const decrypted = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv,
    },
    wrappingKey,
    encryptedBytes,
  );

  return JSON.parse(textDecoder.decode(decrypted));
};

const importPrivateKey = (privateKeyJwk) =>
  window.crypto.subtle.importKey(
    'jwk',
    privateKeyJwk,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    ['deriveBits', 'deriveKey'],
  );

const importPeerPublicKey = (publicKeyJwk) =>
  window.crypto.subtle.importKey(
    'jwk',
    publicKeyJwk,
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    [],
  );

const buildSharedKeyCacheId = ({ userId, peerUserId, peerPublicKeyJwk }) =>
  `${userId}:${peerUserId}:${peerPublicKeyJwk.x}:${peerPublicKeyJwk.y}`;

const ensurePrivateKeyForUser = async (userId) => {
  assertWebCrypto();

  if (privateKeyCache.has(userId)) {
    return privateKeyCache.get(userId);
  }

  const identityKey = `${IDENTITY_PREFIX}${userId}`;
  const storedRaw = window.localStorage.getItem(identityKey);
  const deviceSecret = getOrCreateDeviceSecret();

  if (storedRaw) {
    const stored = JSON.parse(storedRaw);
    const decrypted = await decryptPrivateKeyPayload({
      envelope: stored.encryptedPrivateKey,
      secret: deviceSecret,
    });

    const privateKey = await importPrivateKey(decrypted.privateKeyJwk);
    const identity = {
      privateKey,
      publicKeyJwk: stored.publicKeyJwk,
    };
    privateKeyCache.set(userId, identity);
    return identity;
  }

  const keyPair = await window.crypto.subtle.generateKey(
    {
      name: 'ECDH',
      namedCurve: 'P-256',
    },
    true,
    ['deriveBits', 'deriveKey'],
  );

  const publicKeyJwk = await window.crypto.subtle.exportKey('jwk', keyPair.publicKey);
  const privateKeyJwk = await window.crypto.subtle.exportKey('jwk', keyPair.privateKey);

  const encryptedPrivateKey = await encryptPrivateKeyPayload({
    payload: { privateKeyJwk },
    secret: deviceSecret,
  });

  window.localStorage.setItem(
    identityKey,
    JSON.stringify({
      version: 1,
      publicKeyJwk,
      encryptedPrivateKey,
    }),
  );

  const identity = {
    privateKey: keyPair.privateKey,
    publicKeyJwk,
  };
  privateKeyCache.set(userId, identity);
  return identity;
};

const deriveConversationKey = async ({ userId, peerUserId, peerPublicKeyJwk }) => {
  assertWebCrypto();

  const cacheId = buildSharedKeyCacheId({ userId, peerUserId, peerPublicKeyJwk });

  if (sharedKeyCache.has(cacheId)) {
    return sharedKeyCache.get(cacheId);
  }

  const identity = await ensurePrivateKeyForUser(userId);
  const peerPublicKey = await importPeerPublicKey(peerPublicKeyJwk);
  const sharedSecretBits = await window.crypto.subtle.deriveBits(
    {
      name: 'ECDH',
      public: peerPublicKey,
    },
    identity.privateKey,
    256,
  );

  const aesKey = await window.crypto.subtle.importKey(
    'raw',
    sharedSecretBits,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );

  sharedKeyCache.set(cacheId, aesKey);
  return aesKey;
};

const normalizeEncryptedPayload = (payload) => {
  if (!payload) {
    throw new Error('Missing encrypted payload');
  }

  const parsed = typeof payload === 'string' ? JSON.parse(payload) : payload;

  if (parsed.v !== 1 || parsed.alg !== 'AES-256-GCM') {
    throw new Error('Unsupported encrypted payload format');
  }

  if (!parsed.iv || !parsed.ciphertext) {
    throw new Error('Invalid encrypted payload');
  }

  return parsed;
};

export const ensureUserE2EEIdentity = async (userId) => {
  const identity = await ensurePrivateKeyForUser(userId);
  return {
    publicKeyJwk: identity.publicKeyJwk,
  };
};

export const encryptConversationText = async ({
  userId,
  peerUserId,
  peerPublicKeyJwk,
  plaintext,
}) => {
  const key = await deriveConversationKey({
    userId,
    peerUserId,
    peerPublicKeyJwk,
  });
  const iv = randomBytes(12);
  const encrypted = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
    },
    key,
    textEncoder.encode(String(plaintext)),
  );

  return {
    v: 1,
    alg: 'AES-256-GCM',
    iv: bytesToBase64(iv),
    ciphertext: bytesToBase64(new Uint8Array(encrypted)),
  };
};

export const decryptConversationText = async ({
  userId,
  peerUserId,
  peerPublicKeyJwk,
  payload,
}) => {
  const normalized = normalizeEncryptedPayload(payload);
  const key = await deriveConversationKey({
    userId,
    peerUserId,
    peerPublicKeyJwk,
  });

  const decrypted = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: base64ToBytes(normalized.iv),
    },
    key,
    base64ToBytes(normalized.ciphertext),
  );

  return textDecoder.decode(decrypted);
};

export const clearE2EECaches = () => {
  privateKeyCache.clear();
  sharedKeyCache.clear();
};
