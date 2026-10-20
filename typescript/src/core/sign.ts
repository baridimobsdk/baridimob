import { createSign } from 'node:crypto';

export const INITIAL_STAMP = '00000000000000000000';

function rsaSha1Hex(payload: string, privateKeyPem: string): string {
  const signer = createSign('RSA-SHA1');
  signer.update(payload);
  signer.end();
  return signer.sign(privateKeyPem).toString('hex');
}

export function signParams(params: Record<string, string>, privateKeyPem: string): string {
  const withPlaceholder: Record<string, string> = { ...params, stamp: INITIAL_STAMP };
  const unsigned = new URLSearchParams(withPlaceholder).toString();
  const marker = `stamp=${INITIAL_STAMP}`;
  const signature = rsaSha1Hex(unsigned, privateKeyPem);
  return unsigned.replace(marker, `stamp=${signature}`);
}

export function signJsonBody(body: Record<string, unknown>, privateKeyPem: string): string {
  const withPlaceholder: Record<string, unknown> = { ...body, stamp: INITIAL_STAMP };
  const unsigned = JSON.stringify(withPlaceholder);
  const marker = `"stamp":${JSON.stringify(INITIAL_STAMP)}`;
  const signature = rsaSha1Hex(unsigned, privateKeyPem);
  return unsigned.replace(marker, `"stamp":"${signature}"`);
}
