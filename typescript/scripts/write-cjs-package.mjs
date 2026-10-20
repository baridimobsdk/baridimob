import { writeFileSync } from 'node:fs';

const target = new URL('../dist-cjs/package.json', import.meta.url);
writeFileSync(target, `${JSON.stringify({ type: 'commonjs' }, null, 2)}\n`);
