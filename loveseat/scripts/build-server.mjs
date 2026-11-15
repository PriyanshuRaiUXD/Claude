// Bundles the TypeScript server into a single ESM file that plain `node` can run.
import { build } from 'esbuild';

await build({
  entryPoints: ['server/index.ts'],
  outfile: 'dist/server/index.js',
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node20',
  packages: 'external',
  sourcemap: true,
  // `npm start` runs the built bundle, which should always behave as production.
  define: { 'process.env.LOVESEAT_BUILT': '"1"' },
});
console.log('server bundle → dist/server/index.js');
