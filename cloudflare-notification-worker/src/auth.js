/**
 * Authentication and Token Verification using Web Crypto API.
 * Validates Google Firebase Auth ID Tokens against Google's public certificates.
 */

// In-memory cache for Google public certificates in Cloudflare Worker isolate
let cachedCertificates = null;
let certsExpiry = 0;

/**
 * Base64URL decoder helpers
 */
function base64UrlDecode(str) {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  while (str.length % 4) {
    str += '=';
  }
  const binaryStr = atob(str);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }
  return bytes;
}

function base64UrlDecodeJson(str) {
  const bytes = base64UrlDecode(str);
  const text = new TextDecoder().decode(bytes);
  return JSON.parse(text);
}

/**
 * Converts a PEM certificate string to an ArrayBuffer of DER bytes.
 */
function pemToArrayBuffer(pem) {
  const b64Lines = pem.replace(/-----BEGIN CERTIFICATE-----/, '').replace(/-----END CERTIFICATE-----/, '').replace(/\s+/g, '');
  const raw = atob(b64Lines);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) {
    bytes[i] = raw.charCodeAt(i);
  }
  return bytes.buffer;
}

/**
 * Fetches and caches Google's public x509 certificates for Firebase ID token verification.
 */
async function getGooglePublicCerts() {
  const now = Date.now();
  if (cachedCertificates && now < certsExpiry) {
    return cachedCertificates;
  }

  const res = await fetch('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
  if (!res.ok) {
    throw new Error(`Failed to fetch Google public certificates: ${res.status}`);
  }

  // Parse Cache-Control max-age header if present
  const cacheControl = res.headers.get('cache-control');
  let maxAge = 3600; // default 1 hour
  if (cacheControl) {
    const match = cacheControl.match(/max-age=(\d+)/);
    if (match) {
      maxAge = parseInt(match[1], 10);
    }
  }

  cachedCertificates = await res.json();
  certsExpiry = now + maxAge * 1000;
  return cachedCertificates;
}

/**
 * Extracts public key from x509 certificate and imports into Web Crypto.
 */
async function importX509Cert(certPem) {
  // Convert PEM to DER
  const der = pemToArrayBuffer(certPem);

  // Modern Cloudflare Workers / Node support x509 cert import via Web Crypto or spki
  // We can import raw DER or use crypto.subtle.importKey
  try {
    return await crypto.subtle.importKey(
      'spki',
      extractSpkiFromCert(der),
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['verify']
    );
  } catch (err) {
    // Fallback if SPKI direct extraction is needed
    throw new Error(`Certificate key import failed: ${err.message}`);
  }
}

/**
 * Helper to parse SPKI from simple ASN.1 X.509 DER
 */
function extractSpkiFromCert(certDer) {
  const uint8 = new Uint8Array(certDer);
  // Find the SubjectPublicKeyInfo in the X.509 structure
  // ASN.1 Sequence for rsaEncryption OID 1.2.840.113549.1.1.1: 06 09 2A 86 48 86 F7 0D 01 01 01
  const rsaOid = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];
  let oidIndex = -1;
  for (let i = 0; i < uint8.length - rsaOid.length; i++) {
    let match = true;
    for (let j = 0; j < rsaOid.length; j++) {
      if (uint8[i + j] !== rsaOid[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      oidIndex = i;
      break;
    }
  }

  if (oidIndex === -1) {
    throw new Error('Could not locate RSA OID in certificate');
  }

  // Walk backwards to find the sequence containing AlgorithmIdentifier and SubjectPublicKey
  // Typically 2 bytes before the AlgorithmIdentifier sequence
  let seqStart = oidIndex - 2;
  while (seqStart > 0 && uint8[seqStart] !== 0x30) {
    seqStart--;
  }

  // Go back to the outer SubjectPublicKeyInfo sequence
  let spkiStart = seqStart - 1;
  while (spkiStart > 0 && uint8[spkiStart] !== 0x30) {
    spkiStart--;
  }

  // Find length of SPKI sequence
  let spkiLen = 0;
  let headerLen = 2;
  if (uint8[spkiStart + 1] === 0x81) {
    spkiLen = uint8[spkiStart + 2];
    headerLen = 3;
  } else if (uint8[spkiStart + 1] === 0x82) {
    spkiLen = (uint8[spkiStart + 2] << 8) | uint8[spkiStart + 3];
    headerLen = 4;
  } else {
    spkiLen = uint8[spkiStart + 1];
  }

  const spkiBytes = uint8.slice(spkiStart, spkiStart + headerLen + spkiLen);
  return spkiBytes.buffer;
}

/**
 * Verifies a Firebase Auth ID Token (JWT).
 *
 * @param {string} idToken - Raw Bearer token
 * @param {string} projectId - Expected Firebase project ID
 * @param {string[]} allowedEmails - List of allowed admin email addresses
 * @returns {Promise<{ uid: string, email: string, claims: object }>}
 */
export async function verifyFirebaseAuthToken(idToken, projectId, allowedEmails = []) {
  if (!idToken || typeof idToken !== 'string') {
    throw new Error('Missing or invalid Authorization token');
  }

  const parts = idToken.split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed JWT token structure');
  }

  const [headerB64, payloadB64, signatureB64] = parts;
  const header = base64UrlDecodeJson(headerB64);
  const payload = base64UrlDecodeJson(payloadB64);

  // Validate header
  if (header.alg !== 'RS256') {
    throw new Error(`Invalid token algorithm: ${header.alg}. Expected RS256.`);
  }
  if (!header.kid) {
    throw new Error('Token header is missing "kid"');
  }

  // Validate standard Firebase claims
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) {
    throw new Error('Firebase ID token has expired');
  }
  if (payload.iat && payload.iat > now + 300) {
    throw new Error('Firebase ID token issued in the future');
  }
  if (projectId) {
    if (payload.aud !== projectId) {
      throw new Error(`Invalid token audience: ${payload.aud}. Expected: ${projectId}`);
    }
    if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
      throw new Error(`Invalid token issuer: ${payload.iss}`);
    }
  }
  if (!payload.sub || typeof payload.sub !== 'string') {
    throw new Error('Token payload missing subject (uid)');
  }

  // Verify signature against Google certificates
  const certs = await getGooglePublicCerts();
  const certPem = certs[header.kid];
  if (!certPem) {
    throw new Error(`Public key with kid "${header.kid}" not found in Google certificates`);
  }

  const cryptoKey = await importX509Cert(certPem);
  const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signatureBytes = base64UrlDecode(signatureB64);

  const isValid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    signatureBytes,
    signedData
  );

  if (!isValid) {
    throw new Error('Firebase ID token cryptographic signature is invalid');
  }

  // Check Admin Authorization
  const userEmail = (payload.email || '').toLowerCase().trim();
  const normalizedAllowed = allowedEmails.map(e => e.toLowerCase().trim()).filter(Boolean);

  if (normalizedAllowed.length > 0 && !normalizedAllowed.includes(userEmail)) {
    // Check if user has custom admin claims
    if (payload.role !== 'Admin' && payload.admin !== true) {
      throw new Error(`User "${userEmail || payload.sub}" is not authorized as an Admin`);
    }
  }

  return {
    uid: payload.sub,
    email: userEmail,
    claims: payload,
  };
}
