import { appendFileSync } from "node:fs";

const repository = process.env.GITHUB_REPOSITORY;
if (repository !== "vinialveslopesanjos/crm-mazylabs") {
  throw new Error("Deploy permitido apenas no fork MazyLabs.");
}

async function get(path) {
  const response = await fetch(`https://api.github.com/repos/${repository}/${path}`, {
    headers: {
      Authorization: `Bearer ${process.env.GH_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`GitHub respondeu HTTP ${response.status}.`);
  return response.json();
}

const main = await get("git/ref/heads/main");
const sha = main.object.sha;
if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error("SHA inválido.");
const candidate = process.env.CANDIDATE_SHA || sha;
let ready = false;
if (candidate === sha) {
  const checks = await get(`commits/${sha}/check-runs?filter=latest&per_page=100`);
  if (checks.total_count >= 100) throw new Error("Lista de checks pode estar truncada.");
  const required = ["verify", "invariants", "build-and-size", "e2e", "imagens-ok"];
  const results = required.map((name) => {
    const check = checks.check_runs.find(
      (item) => item.name === name && item.app.slug === "github-actions",
    );
    const ok = check?.status === "completed" && check.conclusion === "success";
    process.stdout.write(`${name}: ${check?.conclusion || check?.status || "aguardando"}\n`);
    return ok;
  });
  ready = results.every(Boolean);
} else {
  process.stdout.write("Uma versão mais nova já está na main; este evento foi superado.\n");
}
appendFileSync(process.env.GITHUB_OUTPUT, `ready=${ready}\nsha=${sha}\n`);
