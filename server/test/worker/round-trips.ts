/** A D1 wrapper that counts round trips: one per `batch` and one per `first`/`all`/`run`/`raw` on a single statement. */
export function countingDB(db: D1Database): { db: D1Database; trips: () => number } {
  let trips = 0;
  const real = new WeakMap<object, D1PreparedStatement>();
  const wrap = (statement: D1PreparedStatement): D1PreparedStatement => {
    const proxy: D1PreparedStatement = new Proxy(statement, {
      get(target, prop) {
        const value = Reflect.get(target, prop, target);
        if (typeof value !== "function") return value;
        if (prop === "bind") return (...values: unknown[]) => wrap(target.bind(...values));
        if (prop === "first" || prop === "all" || prop === "run" || prop === "raw") return (...args: unknown[]) => (trips++, value.apply(target, args));
        return value.bind(target);
      },
    });
    real.set(proxy, statement);
    return proxy;
  };
  const proxy = new Proxy(db, {
    get(target, prop) {
      if (prop === "prepare") return (sql: string) => wrap(target.prepare(sql));
      if (prop === "batch") return (statements: D1PreparedStatement[]) => (trips++, target.batch(statements.map((s) => real.get(s) ?? s)));
      const value = Reflect.get(target, prop, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  return { db: proxy, trips: () => trips };
}
