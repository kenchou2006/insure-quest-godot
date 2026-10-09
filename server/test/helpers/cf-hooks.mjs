// Node module hook: resolve the Workers-only `cloudflare:workers` import to a local stub so DO classes load under node:test.
const STUB = new URL('./cloudflare-workers-stub.mjs', import.meta.url).href;
export async function resolve(specifier, context, next) {
  if (specifier === 'cloudflare:workers') return { url: STUB, shortCircuit: true };
  return next(specifier, context);
}
