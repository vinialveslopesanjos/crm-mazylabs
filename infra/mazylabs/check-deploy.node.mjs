import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const sha = "a".repeat(40);
const names = ["verify", "invariants", "build-and-size", "e2e", "imagens-ok"];
const success = names.map((name) => ({
  name,
  app: { slug: "github-actions" },
  status: "completed",
  conclusion: "success",
}));

async function gate({ checks = success, candidate = sha, total = checks.length, fail = false }) {
  const directory = mkdtempSync(join(tmpdir(), "crm-deploy-"));
  const output = join(directory, "output");
  const beforeFetch = globalThis.fetch;
  const beforeEnv = { ...process.env };
  let calls = 0;
  process.env.GITHUB_REPOSITORY = "vinialveslopesanjos/crm-mazylabs";
  process.env.GITHUB_OUTPUT = output;
  process.env.CANDIDATE_SHA = candidate;
  process.env.GH_TOKEN = "token-falso";
  globalThis.fetch = async (url) => {
    calls++;
    if (fail) return { ok: false, status: 403 };
    return {
      ok: true,
      json: async () =>
        String(url).endsWith("git/ref/heads/main")
          ? { object: { sha } }
          : { total_count: total, check_runs: checks },
    };
  };
  try {
    await import(`./check-deploy.mjs?case=${Math.random()}`);
    return { output: readFileSync(output, "utf8"), calls };
  } finally {
    globalThis.fetch = beforeFetch;
    for (const key of ["GITHUB_REPOSITORY", "GITHUB_OUTPUT", "CANDIDATE_SHA", "GH_TOKEN"]) {
      if (beforeEnv[key] === undefined) delete process.env[key];
      else process.env[key] = beforeEnv[key];
    }
    rmSync(directory, { recursive: true, force: true });
  }
}

test("libera somente quando todos os checks do commit atual passaram", async () => {
  const result = await gate({});
  assert.match(result.output, /^ready=true\n/);
  assert.match(result.output, new RegExp(`sha=${sha}`));
});

test("check pendente, ausente, cancelado ou reprovado impede deploy", async () => {
  for (const conclusion of [null, "failure", "cancelled"]) {
    const checks = success.map((check) =>
      check.name === "verify"
        ? { ...check, status: conclusion === null ? "in_progress" : "completed", conclusion }
        : check,
    );
    assert.match((await gate({ checks })).output, /^ready=false\n/);
  }
  assert.match((await gate({ checks: success.slice(1) })).output, /^ready=false\n/);
});

test("evento de commit antigo não consulta checks nem libera deploy", async () => {
  const result = await gate({ candidate: "b".repeat(40) });
  assert.equal(result.calls, 1);
  assert.match(result.output, /^ready=false\n/);
});

test("check com o mesmo nome vindo de outro app não vale como aprovação", async () => {
  const checks = success.map((check) => ({ ...check, app: { slug: "outro-app" } }));
  assert.match((await gate({ checks })).output, /^ready=false\n/);
});

test("erro de API ou lista truncada reprova em vez de publicar", async () => {
  await assert.rejects(gate({ fail: true }), /HTTP 403/);
  await assert.rejects(gate({ total: 100 }), /truncada/);
});
