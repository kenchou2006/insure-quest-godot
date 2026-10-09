/* Fake DurableObjectState for unit-testing Room / Records outside workerd. */
import { DatabaseSync } from 'node:sqlite';

export class FakeSocket {
  att: unknown = null;
  sent: any[] = [];
  closed = false;
  owner: FakeState;
  constructor(owner: FakeState) { this.owner = owner; }
  serializeAttachment(a: unknown) { this.att = structuredClone(a); }
  deserializeAttachment() { return this.att; }
  send(d: string) { if (this.closed) throw new Error('closed'); this.sent.push(JSON.parse(d)); }
  close() { this.closed = true; this.owner.sockets = this.owner.sockets.filter(s => s !== this); }
  last(t: string) { return [...this.sent].reverse().find(m => m.t === t); }
}

/** Wraps node:sqlite to mimic `ctx.storage.sql.exec(query, ...binds)` cursors. */
function fakeSql(db: DatabaseSync) {
  return {
    exec(query: string, ...binds: any[]) {
      const st = db.prepare(query);
      const rows = st.columns().length ? (st.all(...binds) as any[]) : (st.run(...binds), []);
      return { toArray: () => rows, one: () => { if (rows.length !== 1) throw new Error('expected one row'); return rows[0]; } };
    },
  };
}

export class FakeState {
  kv = new Map<string, unknown>();
  alarm: number | null = null;
  sockets: FakeSocket[] = [];
  ready: Promise<unknown> = Promise.resolve();
  db = new DatabaseSync(':memory:');
  storage = {
    get: async (k: string) => structuredClone(this.kv.get(k)),
    put: async (k: string, v: unknown) => { this.kv.set(k, structuredClone(v)); },
    deleteAll: async () => { this.kv.clear(); },
    setAlarm: async (t: number) => { this.alarm = t; },
    deleteAlarm: async () => { this.alarm = null; },
    getAlarm: async () => this.alarm,
    sql: fakeSql(this.db),
  };
  blockConcurrencyWhile(fn: () => Promise<unknown>) { this.ready = fn(); return this.ready; }
  waitUntil(_p: Promise<unknown>) {}
  getWebSockets() { return [...this.sockets]; }
  /** Simulates the Worker accepting a WebSocket for this room (what /ws does). */
  connect(account: { id: string; name: string } | null = null) {
    const ws = new FakeSocket(this);
    ws.serializeAttachment({ playerId: null, accountId: account?.id ?? null, accountName: account?.name ?? null });
    this.sockets.push(ws);
    return ws;
  }
}
