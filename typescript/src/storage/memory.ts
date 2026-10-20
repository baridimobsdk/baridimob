import type { SessionStorage, StoredSession } from '../types.js';

export function memoryStorage(initial?: StoredSession): SessionStorage {
  let current: StoredSession | null = initial ? structuredClone(initial) : null;
  return {
    async load() {
      return current ? structuredClone(current) : null;
    },
    async save(session) {
      current = structuredClone(session);
    },
    async clear() {
      current = null;
    },
  };
}
