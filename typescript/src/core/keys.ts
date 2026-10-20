import { createHash, createPublicKey, generateKeyPairSync, randomUUID } from 'node:crypto';

export const DEVKEY_ALGORITHM = 'RSA 2048';

export const DEVKEY_ALGORITHM_HASH = '2irTxfGZWzVtenv242nedCNNC9k3M64egLmFRV8V4tk=';
export interface DeviceKeys {
  devid: string;
  privateKeyPem: string;
  devkey: string;
  devkeyAlgorithm: string;
  devkeyAlgorithmHash: string;
}

export function algorithmHash(algorithm: string): string {
  return createHash('sha256').update(algorithm).digest('base64');
}

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export function deriveDevkey(publicKeyPem: string): string {
  const der = createPublicKey(publicKeyPem).export({ type: 'spki', format: 'der' }) as Buffer;
  const start = der.length > 100 ? 24 : 20;
  return der.subarray(start).toString('hex');
}

export function generateDeviceKeys(bits: 2048 | 512 = 2048): DeviceKeys {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: bits,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  const devkeyAlgorithm = bits === 2048 ? 'RSA 2048' : 'RSA 512';
  return {
    devid: randomUUID(),
    privateKeyPem: privateKey,
    devkey: deriveDevkey(publicKey),
    devkeyAlgorithm,
    devkeyAlgorithmHash: algorithmHash(devkeyAlgorithm),
  };
}
