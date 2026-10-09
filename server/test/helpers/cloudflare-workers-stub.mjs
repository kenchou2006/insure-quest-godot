// Minimal stand-in for the Workers runtime base class used by Room and Records.
export class DurableObject {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; }
}
