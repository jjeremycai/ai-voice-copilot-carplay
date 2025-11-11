import jwt from 'jsonwebtoken';
import https from 'https';

const ASC_ISSUER_ID = process.env.ASC_ISSUER_ID;
const ASC_KEY_ID = process.env.ASC_KEY_ID;
const ASC_PRIVATE_KEY_P8 = process.env.ASC_PRIVATE_KEY_P8;
const ASC_ENV = process.env.ASC_ENV || 'Sandbox';

const APPLE_API_BASE = ASC_ENV === 'Production'
  ? 'https://api.storekit.googleapis.com'
  : 'https://api.storekit-sandbox.googleapis.com';

function generateAppStoreConnectToken() {
  if (!ASC_ISSUER_ID || !ASC_KEY_ID || !ASC_PRIVATE_KEY_P8) {
    throw new Error('Apple App Store Connect credentials not configured');
  }

  const now = Math.floor(Date.now() / 1000);

  const privateKey = Buffer.from(ASC_PRIVATE_KEY_P8, 'base64').toString('utf-8');

  const token = jwt.sign({}, privateKey, {
    algorithm: 'ES256',
    expiresIn: '20m',
    audience: 'appstoreconnect-v1',
    issuer: ASC_ISSUER_ID,
    header: {
      alg: 'ES256',
      kid: ASC_KEY_ID,
      typ: 'JWT'
    }
  });

  return token;
}

function makeAppleAPIRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const token = generateAppStoreConnectToken();
    const url = new URL(path, APPLE_API_BASE);

    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            resolve(data);
          }
        } else {
          reject(new Error(`Apple API error: ${res.statusCode} - ${data}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    if (body) {
      req.write(JSON.stringify(body));
    }

    req.end();
  });
}

export async function verifyTransaction(transactionJWS) {
  const parts = transactionJWS.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWS format');
  }

  const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf-8'));

  const transactionId = payload.transactionId;
  const originalTransactionId = payload.originalTransactionId;
  const productId = payload.productId;
  const purchaseDate = new Date(payload.purchaseDate);
  const expiresDate = payload.expiresDate ? new Date(payload.expiresDate) : null;
  const environment = payload.environment;

  let status = 'expired';
  let isInGrace = false;

  if (expiresDate) {
    const now = new Date();
    const gracePeriodEnd = new Date(expiresDate.getTime() + (16 * 24 * 60 * 60 * 1000)); // 16 days grace

    if (now < expiresDate) {
      status = 'active';
    } else if (now < gracePeriodEnd) {
      status = 'grace';
      isInGrace = true;
    }
  }

  return {
    transactionId,
    originalTransactionId,
    productId,
    purchaseDate,
    expiresAt: expiresDate,
    environment,
    status,
    isInGrace
  };
}

export async function parseAppStoreServerNotification(signedPayload) {
  const parts = signedPayload.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid ASN JWS format');
  }

  const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf-8'));

  const notificationType = payload.notificationType;
  const subtype = payload.subtype;

  const transactionInfo = payload.data?.signedTransactionInfo;
  if (!transactionInfo) {
    throw new Error('No transaction info in notification');
  }

  const txParts = transactionInfo.split('.');
  const txPayload = JSON.parse(Buffer.from(txParts[1], 'base64').toString('utf-8'));

  return {
    notificationType,
    subtype,
    transaction: {
      originalTransactionId: txPayload.originalTransactionId,
      productId: txPayload.productId,
      expiresAt: txPayload.expiresDate ? new Date(txPayload.expiresDate) : null,
      environment: txPayload.environment
    }
  };
}

export function getEnvironment() {
  return ASC_ENV;
}

export function isConfigured() {
  return !!(ASC_ISSUER_ID && ASC_KEY_ID && ASC_PRIVATE_KEY_P8);
}
