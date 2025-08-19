import { describe, it, expect } from "vitest";
import health from "../../apps/api/src/routes/health.mjs";

function createRes() {
  let statusCode = 200;
  let body = null;
  return {
    status(code) { statusCode = code; return this },
    json(payload) { body = payload; return this },
    _read() { return { statusCode, body } }
  };
}

describe("GET /health", () => {
  it("200 dönmeli", () => {
    const res = createRes();
    // @ts-expect-error minimal req/res
    health({}, res);
    const out = res._read();
    expect(out.statusCode).toBe(200);
  });

  it("şema { ok:true, ts:number } olmalı", () => {
    const res = createRes();
    // @ts-expect-error minimal req/res
    health({}, res);
    const { body } = res._read();
    expect(body && body.ok).toBe(true);
    expect(typeof body.ts).toBe("number");
  });

  it("sentetik hata örneği yakalanır", () => {
    const boom = () => { throw new Error("boom") };
    expect(boom).toThrow("boom");
  });
});
