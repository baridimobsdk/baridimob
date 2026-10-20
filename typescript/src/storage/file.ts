import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { BaridiMobError } from '../core/errors.js';
import type { SessionStorage, StoredSession } from '../types.js';

export function fileStorage(path: string): SessionStorage {
  return {
    async load() {
      let raw: string;
      try {
        raw = await readFile(path, 'utf8');
      } catch (error) {
        if (isMissingFile(error)) return null;
        throw error;
      }
      try {
        return JSON.parse(raw) as StoredSession;
      } catch (error) {
        throw new BaridiMobError(`Corrupted session file: ${path}`, { cause: error });
      }
    },
    async save(session) {
      await mkdir(dirname(path), { recursive: true, mode: 0o700 });
      await writeFile(path, `${JSON.stringify(session, null, 2)}\n`, { mode: 0o600 });
    },
    async clear() {
      await rm(path, { force: true });
    },
  };
}

function isMissingFile(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code?: unknown }).code === 'ENOENT'
  );
}
