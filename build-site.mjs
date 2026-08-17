/* ==========================================================================
   fleetprompt.com site build.

       node build-site.mjs   (run it through the gate: ./site.sh)

   The landing page is GENERATED. Every count that reaches it is RECOMPUTED
   here by RUNNING THE SUITES — `mix test` in this repository and `vitest` in
   npm/ — and parsing what they print. If a recomputed count disagrees with the
   frozen record in records/tests.json, this build throws and nothing is
   emitted.

   The direction of dependency is the whole point (SHELL.md §4.1). The page
   cell is COMPUTED; the record is what it is CHECKED AGAINST. If the page were
   the source, nothing could audit it — and this repository has already shipped
   one number that was true of a different scope than the sentence around it.

   r8: the artifact is written to a temp name, READ BACK, re-hashed, and only
   then renamed into place. The hashes go into records/build.json so the gate
   can prove the file it reads is this build's output and not a survivor of a
   build that threw. That failure mode is not hypothetical — it made two
   deliberate gate breaks report PASS on a sibling surface.
   ========================================================================== */
import { readFileSync, writeFileSync, existsSync, renameSync, unlinkSync } from "fs";
import { execFileSync } from "child_process";
import { createHash } from "crypto";

const read = (p) => readFileSync(p, "utf8");
const J = (p) => JSON.parse(read(p));
const sha = (s) => createHash("sha256").update(s).digest("hex");

const surface = J("./records/surface.json");
const SPEC_URL = "https://docs.ampersandboxdesign.com/#/fleetprompt.com/docs/spec/README.md";
const RUNGS = ["spec", "in_tree", "live_local", "live_deployed", "external"];

/* ---------- release identity: the Elixir app's version, or no build ----------
   These repositories have no package.json at the root and inventing one so the
   shell's usual check has something to read would be inventing the evidence.
   mix.exs is where this project's version actually lives. */
const mixVersion = (() => {
    const m = /version:\s*"([^"]+)"/.exec(read("./mix.exs"));
    if (!m) throw new Error("BUILD REFUSED — no version found in mix.exs");
    return m[1];
})();
if (mixVersion !== surface.version) {
    throw new Error(
        `BUILD REFUSED — release identity: mix.exs ${mixVersion} != records/surface.json ${surface.version}`
    );
}
const STAMP = `FLEETPROMPT v${surface.version} · RECORDS ${surface.verified_at}`;

const esc = (s) =>
    String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");

/* ==========================================================================
   THE CONSISTENCY GATE — run the suites, do not quote them.
   ========================================================================== */
function runSuite(label, cmd, args, cwd) {
    let out;
    try {
        out = execFileSync(cmd, args, {
            cwd,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env, MIX_ENV: "test", NO_COLOR: "1", FORCE_COLOR: "0" },
            timeout: 600000,
        });
    } catch (e) {
        /* A non-zero exit is a failing suite, and a failing suite is a build
           refusal — but read the output first, because ExUnit exits non-zero
           WITH a usable summary line, and "the command failed" is a less
           useful message than "114 tests, 2 failures". */
        out = `${e.stdout || ""}${e.stderr || ""}`;
        if (!out.trim()) throw new Error(`BUILD REFUSED — ${label} did not run: ${e.message}`);
    }
    /* eslint-disable-next-line no-control-regex */
    return out.replace(/\[[0-9;]*m/g, "");
}

/* ExUnit: "112 tests, 0 failures (2 excluded)" */
function exunit(label, args) {
    const out = runSuite(label, "mix", args, ".");
    const m = /(\d+)\s+tests?,\s+(\d+)\s+failures?(?:\s*\((\d+)\s+excluded\))?/.exec(out);
    if (!m) throw new Error(`BUILD REFUSED — ${label} printed no summary this build could parse`);
    return { total: Number(m[1]), failures: Number(m[2]), excluded: m[3] ? Number(m[3]) : 0 };
}
const dflt = exunit("mix test", ["test"]);
/* And the same suite with the excluded tag included, so the page can publish
   what happens when it is — rather than reporting a green count that quietly
   depends on two tests not running. They fail; that is the honest row. */
const full = exunit("mix test --include live_crystallization", ["test", "--include", "live_crystallization"]);

const suites = [
    { id: "default", label: "mix test", runner: "ExUnit, default tags", ...dflt },
    { id: "full", label: "mix test --include live_crystallization", runner: "ExUnit, nothing excluded", ...full },
];
const TOTAL = full.total;

const drift = [];
if (dflt.failures !== 0) drift.push(`mix test: ${dflt.failures} failing under default tags`);
if (full.total !== dflt.total + dflt.excluded) {
    drift.push(`the excluded count does not account for the difference: ${dflt.total} + ${dflt.excluded} != ${full.total}`);
}

/* records/tests.json is written by this build the first time and CHECKED
   against on every run afterwards. Freezing it is what turns "the numbers came
   out of the suite" into "the numbers have not moved since a person looked". */
const FROZEN = "./records/tests.json";
if (existsSync(FROZEN)) {
    const frozen = J(FROZEN);
    for (const f of frozen.suites) {
        const c = suites.find((x) => x.id === f.id);
        if (!c) {
            drift.push(`${f.id}: in the record, not in this build`);
            continue;
        }
        for (const k of ["total", "failures", "excluded"]) {
            if (c[k] !== f[k]) drift.push(`${f.id} ${k}: ran ${c[k]} != record ${f[k]}`);
        }
    }
    if (frozen.total !== TOTAL) drift.push(`total: ran ${TOTAL} != record ${frozen.total}`);
} else {
    writeFileSync(
        FROZEN,
        JSON.stringify(
            {
                schema: "computedriven-tests-v1",
                _comment:
                    "Frozen by build-site.mjs on first run. Every value is re-derived by RUNNING the suites on every subsequent build and the build refuses on any disagreement. Do not hand-edit: if a suite changes what it counts, that is an event, not a typo.",
                frozen_at: surface.verified_at,
                total: TOTAL,
                suites: suites.map(({ id, label, runner, total, failures, excluded }) => ({
                    id,
                    label,
                    runner,
                    total,
                    failures,
                    excluded,
                })),
            },
            null,
            2
        ) + "\n"
    );
    console.log(`froze ${suites.length} suites into ${FROZEN}`);
}

if (drift.length) {
    console.error("BUILD REFUSED — the suites and the frozen record disagree:");
    drift.forEach((d) => console.error("  " + d));
    process.exit(1);
}
console.log(
    `consistency gate: ${suites.length} suites re-run, ${TOTAL} tests, 0 failures, 0 drift`
);

/* Every command this page tells a reader to run must be a command that runs.
   The sibling repository shipped a quick-start whose first line threw, for
   months, because nobody ever executed a documented path. */
{
    const quick = read("./README.md");
    for (const cmd of ["mix test", "mix deps.get"]) {
        if (!quick.includes(cmd)) drift.push(`README no longer documents \`${cmd}\``);
    }
    if (drift.length) {
        console.error("BUILD REFUSED —");
        drift.forEach((d) => console.error("  " + d));
        process.exit(1);
    }
}

/* ==========================================================================
   SHELL FRAGMENTS — shared markup; only the tokens in src/shell.css differ.
   ========================================================================== */

/* The chip renders the stored rung, and "?" when there is none. It never
   defaults, because a defaulted rung is a fabricated status. */
function rung(value) {
    const r = RUNGS.includes(value) ? value : "?";
    return `<span class="rung" data-rung="${r}" title="spec · in_tree · live_local · live_deployed · external">${r}</span>`;
}

/* THE BAND STATES WHERE YOU ARE, AND WHAT IT MAY STATE DEPENDS ON THE PLACE.
   ampersand-nav/src/amp-nav.js records specprompt as place:3, and its own
   renderPlacement() emits the layer sentence for place 2 ONLY — place 3 gets
   "a specification in the ComputeDriven world" plus a spec link. This page
   embeds <amp-nav property="specprompt"> immediately beneath this band, so a
   layer sentence here would contradict the nav one element below it. The nav
   is the record and the nav wins. SHELL.md §1, r6. */
function band() {
    const where = {
        4: `A <b>${esc(surface.parent)}</b> project`,
        3: `${esc(surface.surface)} is <b>a specification</b> in the ${esc(surface.parent)} world`,
        2: `${esc(surface.surface)} is the <b>${esc(surface.layer)}</b> layer of ${esc(surface.parent)}`,
    }[surface.tier];
    if (!where) {
        throw new Error(
            "BUILD REFUSED — records/surface.json declares no usable place, so the band cannot know what it may claim."
        );
    }
    const link =
        surface.tier === 3
            ? `<a class="spec-link" href="${SPEC_URL}">the specification &rarr;</a>`
            : "";
    return `<div class="band" data-tier="${surface.tier}"><span class="where">${where}</span>${rung(
        surface.surface_rung
    )}<span class="covers">That rung covers ${esc(surface.surface_rung_covers)}.</span>${link}</div>`;
}

function statusBlock() {
    const s = surface.status;
    return `<dl class="status">
<div><dt>Status</dt><dd><strong>${esc(surface.surface_rung)}</strong> &mdash; ${esc(s.statement)}</dd></div>
<div><dt>Last verified</dt><dd>${esc(surface.verified_at)}</dd></div>
<div><dt>Source</dt><dd>${esc(s.source)}</dd></div>
<div class="limit"><dt>Limit</dt><dd>${esc(s.limit)}</dd></div>
<div><dt>Next rung</dt><dd><strong>${esc(surface.advance.next_rung)}</strong> &mdash; ${esc(surface.advance.requires)}</dd></div>
</dl>`;
}

/* SITES.md §0.7: the rung gates the call to action. A CTA group declares its
   rung and may only use verbs that rung has earned; anything else throws. */
const VERBS = {
    spec: ["Read", "Challenge", "Implement"],
    in_tree: ["Inspect the source", "Run the tests"],
    live_local: ["Use it", "Reproduce it locally"],
    live_deployed: ["Use the deployed artifact"],
    external: ["See independent evidence", "Contribute another result"],
};

function cta(groupRung, label, actions) {
    const allowed = VERBS[groupRung];
    if (!allowed) throw new Error(`CTA group declares an unknown rung: ${groupRung}`);
    for (const a of actions) {
        if (!allowed.includes(a.verb)) {
            throw new Error(
                `BUILD REFUSED — CTA "${a.verb}" is not available at rung ${groupRung}. Allowed: ${allowed.join(", ")}`
            );
        }
    }
    const cls = groupRung === "spec" ? "tag" : "tag ok";
    return `<div class="ctagroup"><div class="${cls}">${esc(groupRung)} &mdash; ${esc(label)}</div><div class="cta">${actions
        .map(
            (a) =>
                `<a href="${a.href}"${a.href.startsWith("http") ? ' target="_blank" rel="noopener"' : ""}><span class="verb">${esc(a.verb)}</span><span class="what">${a.what}</span></a>`
        )
        .join("")}</div></div>`;
}

/* ==========================================================================
   GENERATED CONTENT

   Every figure is derived from a suite run or from the record. The suffixes
   matter: a bare integer as a text node would collide with any literal of the
   same value in the animation source and refuse the build, and the honest fix
   for that is a label on the number, not a quieter check.
   ========================================================================== */
/* Every plate figure carries its noun IN THE SAME TEXT NODE. A bare integer is
   indistinguishable from a decorative constant to any checker and to any
   reader skimming: gpscoord published `for (i = 0; i < 12; i++)` as "12 Active
   Pathfinders" for months. §8.5 compares whole text nodes, so "2 parsers"
   cannot collide with a line width of 2 in the animation — and the fix is
   permanent for every future figure rather than a dodge of today's one. The
   zero counts keep their bare form: 0 and 1 are structural in any drawing code
   and identify nothing, which is why §8.5 excludes them. */
function plate() {
    const cells = [
        [`${TOTAL} tests`, "Defined in this repository, re-run by this build"],
        [`${dflt.excluded} excluded`, "Tagged out by default — and failing when included"],
        ...surface.zero_counts.map((z) => [z.value, z.label]),
    ];
    return `<div class="grid plate">${cells
        .map(([n, l]) => `<div><div class="n">${esc(n)}</div><div class="l">${esc(l)}</div></div>`)
        .join("")}</div>`;
}


function artifactCards() {
    return `<div class="grid">${surface.artifacts
        .map(
            (a) =>
                `<div><div class="head"><h3>${esc(a.name)}</h3>${rung(a.rung)}</div><p>${esc(a.detail)}</p><div class="needs"><b>Where:</b> <span class="where-tag">${esc(a.where)}</span><br><b>Witness:</b> ${esc(a.witness)}</div></div>`
        )
        .join("")}</div>`;
}

function openCards() {
    return `<div class="grid">${surface.unmeasured
        .map(
            (c) =>
                `<div><div class="head"><h3>${esc(c.name)}</h3>${rung(c.rung)}</div><p>${esc(c.detail)}</p><div class="needs"><b>Needs:</b> ${esc(c.needs)} <b>Built:</b> ${esc(c.built)}.</div></div>`
        )
        .join("")}</div>`;
}

/* The suite table's cells come from the runs above, not from the record. BOTH
   runs are published: a green count that depends on two tests not running is
   half a fact, and the other half is what they do when they run. */
function testsTable() {
    const rows = suites
        .map(
            (x) =>
                `<tr><td class="place"><code>${esc(x.label)}</code></td><td class="num">${x.total} ran</td><td class="num">${x.failures} failing</td><td class="num">${x.excluded} excluded</td><td class="st">${
                    x.failures ? "<b>the two that need a live service</b>" : "<i>green under its own tags</i>"
                }</td></tr>`
        )
        .join("");
    return `<div class="scroll"><table><thead><tr><th>Command</th><th>Ran</th><th>Failed</th><th>Excluded</th><th>What that means</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}


/* The pieces table is the record's own status language, preserved. It is the
   most valuable thing this domain publishes and the shell does not get to
   flatten it into marketing. */
function piecesTable() {
    const rows = surface.pieces
        .map(
            (p) =>
                `<tr><td class="place">${esc(p.piece)}</td><td class="st">${esc(p.what)}</td><td class="st">${
                    p.measured ? `<i>${esc(p.status)}</i>` : `<b>${esc(p.status)}</b>`
                }</td></tr>`
        )
        .join("");
    return `<div class="scroll"><table><thead><tr><th>Piece</th><th>What it is</th><th>Status &mdash; measured or admitted</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

const METHOD_NOTE =
    `Both rows were produced by executing the command in them and parsing what ExUnit printed. The two excluded tests are ` +
    `<code>FleetPrompt.KilnPollWorkerLiveTest</code> &mdash; the live crystallization pipeline &mdash; and they fail in setup because they need a ` +
    `service that is not running here. That is why they are tagged out, and publishing the tagged-out run beside the default one is the only way a ` +
    `reader can tell a green suite from a suite that is green because two tests were removed from it. The build refuses to emit this page if the two ` +
    `runs stop accounting for each other.`;


function zeros() {
    return `<dl class="status">${surface.zero_counts
        .map(
            (z) =>
                `<div><dt>${esc(z.label)}</dt><dd><strong>${esc(z.value)}.</strong> ${esc(z.witness)}</dd></div>`
        )
        .join("")}</dl>`;
}

/* fleetprompt's own figures. Static markup, no script, no data. The entry is
   the registry's ENTIRE contents — the prior page's own framing, kept, because
   showing the whole of a small thing is the argument. The identity string is
   the record's; launch-gate.mjs refuses any other sem- string on the page. */
const ID = surface.identity;
const ENTRY = `<div class="entry">
<div class="hd"><span>fleetprompt registry &mdash; the complete contents</span><span class="tag">not installable</span></div>
<dl>
<dt>Listing</dt><dd>the trvs demo world</dd>
<dt>Identity</dt><dd class="id">${esc(ID.sem_id)}</dd>
<dt>Engine</dt><dd>${esc(ID.engine)} &mdash; <code>trvs doctor</code> reporting status ready on the guest</dd>
<dt>Sealed on</dt><dd>${esc(ID.hosts[0])}</dd>
<dt>Replayed on</dt><dd>${esc(ID.hosts[1])}, ${esc(ID.measured_at)}</dd>
</dl>
<p class="foot">Both stamps are earned, and both are weaker than they look. The guest was created straight from the build pipeline&rsquo;s own image and never touched afterwards &mdash; the verifier and the runtime are in the image now, not copied there by hand &mdash; so this is not a hand-assembled result. It is still <strong>the same implementation on two machines</strong>: one codebase agreeing with itself, which is a portability result and not a semantics one. And the entry is not installable, because the gate that would admit it does not exist.</p>
</div>`;

function stepsFigure() {
    return `<div class="steps">${surface.steps
        .map(
            (x) =>
                `<div class="st"><div class="n">${esc(x.n)}</div><div class="b"><b>${esc(x.verb)}.</b><p>${esc(x.detail)}</p></div><div class="tag">${esc(x.tag)}</div></div>`
        )
        .join("")}</div>`;
}

/* ==========================================================================
   THE RETRACTION
   Both strings below stood on the page this one replaces. They are in
   launch-gate.mjs's blocklist with a hard bound on how many times they may
   occur, so they cannot come back by an edit — only by a ruling.
   ========================================================================== */
const RETRACTION = `<div class="retract"><h3>Retraction &mdash; three things this page used to say</h3>
<p><strong>It published a test count that is not the count of anything here.</strong> The status table read <code>157 tests</code>, and so does <code>docs/ux/user-stories.md</code>. Re-derived on ${esc(surface.verified_at)} by running the suite: 114 tests are defined, <code>mix test</code> runs 112 of them green and excludes 2, and those 2 fail when included because they need a live service. No gate would have caught this &mdash; nothing had ever executed the suite and compared. The build now does, on every run, and refuses the page when the numbers stop accounting for each other.</p>
<p><strong>It claimed a layer.</strong> The previous hero eyebrow read <code>The distribution layer of the ComputeDriven stack</code>. <code>ampersand-nav</code> files this domain as a <em>specification</em> in that world rather than a layer of it. The band now says what the nav says; if the placement is wrong, the fix belongs in the nav, which this repository does not own.</p>
<p><strong>It published an email address.</strong> <code>hello@computedriven.com</code> stood in the footer. Corrections now go through the form above, which posts to the endpoint the parent site uses, and through this repository&rsquo;s issues. No <code>mailto:</code> and no address in the markup &mdash; the gate refuses both.</p>
<p><strong>And the retraction the earlier page made, which stands.</strong> An earlier fleetprompt.com displayed a registry of five agents with trust scores, install counts and a launch date. Not one of the five was a real listing, the numbers beside them were written by hand rather than computed by the trust engine that genuinely exists, and the date passed. The registry above shows its true contents.</p></div>`;


/* ==========================================================================
   THE CORRECTION FORM — SHELL.md r9, ruled by Travis.
   A real form that posts with scripting off. src/form.js upgrades it to an
   inline reply and prints success only on a 2xx.
   ========================================================================== */
const FORM = `<form class="say" action="${surface.contact.endpoint}" method="POST" novalidate>
<div class="say-row">
<label class="say-f"><span>Your email</span><input type="email" name="email" autocomplete="email" placeholder="so a reply can reach you" required></label>
<label class="say-f"><span>Message</span><textarea name="message" rows="3" placeholder="a question, a correction, a number of ours you think is wrong" required></textarea></label>
</div>
<input type="text" name="_gotcha" tabindex="-1" autocomplete="off" aria-hidden="true">
<input type="hidden" name="_subject" value="${esc(STAMP)}">
<div class="say-act"><button type="submit">Send</button><p class="say-msg" role="status" aria-live="polite"></p></div>
</form>
<p class="alt">Or file it in public: <a href="${surface.contact.url}">${esc(surface.contact.url.replace(/^https:\/\//, ""))}</a>. Both reach the same people.</p>`;

/* ==========================================================================
   EMIT — write, read back, re-hash, rename. r8.
   ========================================================================== */
/* The stylesheet ships stripped of comments and indentation. The source stays
   commented and readable; only the artifact is dense. SHELL.md §5. */
const CSS = read("./src/shell.css")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\n\s*/g, "")
    .replace(/;\}/g, "}")
    .trim();

/* The scripts are emitted as their own artifacts rather than inlined, for two
   reasons and the second is the point: the markup stays content-only, so "the
   content is complete with scripting off" is something a reader verifies by
   deleting two lines; and the animation becomes a file the publication gate
   can read constants out of and compare against the page. NEWLINES ARE KEPT —
   joining JavaScript lines the way the CSS is joined is a semicolon-insertion
   bug waiting to happen. */
const stripJs = (p) =>
    read(p)
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^[ \t]*\/\/.*$/gm, "")
        .replace(/^[ \t]+/gm, "")
        .replace(/[ \t]+$/gm, "")
        .replace(/\n{2,}/g, "\n")
        .trim();

const ANIM = stripJs("./src/replay.js");
const FORMJS = stripJs("./src/form.js");
const YEAR = new Date(surface.verified_at).getUTCFullYear();

function fill(tpl, vars) {
    return tpl.replace(/\{\{(\w+)\}\}/g, (m, k) => {
        if (!(k in vars)) throw new Error(`template token {{${k}}} has no value`);
        return vars[k];
    });
}

const landing = fill(read("./src/landing.html"), {
    CSS,
    BAND: band(),
    STAMP,
    ORIGIN: surface.origin,
    APP_ORIGIN: surface.app_origin,
    REPO: surface.repo,
    ISSUES: surface.contact.url,
    SPEC_URL,
    PARENT: surface.parent,
    QUESTION: esc(surface.question),
    YEAR: String(YEAR),
    PLATE: plate(),
    ENTRY,
    STEPS: stepsFigure(),
    ARTIFACTS: artifactCards(),
    OPEN_CARDS: openCards(),
    TESTS_TABLE: testsTable(),
    PIECES_TABLE: piecesTable(),
    METHOD_NOTE,
    STATUS: statusBlock(),
    ZEROS: zeros(),
    RETRACTION,
    FORM,
    CTA:
        cta("live_deployed", "answering on its own host, checked with curl", [
            {
                verb: "Use the deployed artifact",
                href: surface.app_origin,
                what: "The registry service as it exists today: search, publishers, a trust dashboard, a seven-step install engine. It computes trust from four weighted signals and cannot tell you what any listed agent did. It is the thing this page argues past &mdash; and its JSON search endpoint answers every query with a server error, which takes about ten seconds to check.",
            },
        ]) +
        cta("in_tree", "a codebase with a suite, not a replay gate", [
            {
                verb: "Inspect the source",
                href: surface.repo,
                what: "The install engine, the trust engine, the publish flow, version immutability and the MCP tools (&sect;11). Where the replay gate would go is where nothing is.",
            },
            {
                verb: "Run the tests",
                href: surface.repo,
                what: "<code>mix test</code>, then <code>mix test --include live_crystallization</code>. Both counts are in the table above; the second is the one that fails, and it is published for that reason.",
            },
        ]) +
        cta("spec", "a document, and the gate it describes is unwritten", [
            {
                verb: "Read",
                href: SPEC_URL,
                what: "v0.1: manifests (&sect;4), the trust engine (&sect;5), the publish pipeline (&sect;6), the install pipeline (&sect;7). &sect;5 is the model being superseded, which is worth reading on the page that supersedes it.",
            },
            {
                verb: "Challenge",
                href: surface.contact.url,
                what: "Tell us what a receipt would have to contain before you would stake an install on it. <strong>There is deliberately no invitation to publish here</strong> &mdash; the registry has nowhere to put a film, and a page that cannot honour its own call to action is worse than one with none.",
            },
            {
                verb: "Implement",
                href: surface.repo,
                what: "A second verifier that derives the same identity from the same bundle. One implementation agreeing with itself on two operating systems is what this page has; it is not what it needs.",
            },
        ]),
});

/* Write, read back, re-hash, rename. A gate that reads the artifact must be
   able to say the artifact came from the source beside it, and the only way to
   say that is to hash what actually landed on disk. */
const emitted = [
    ["./index.html", landing],
    ["./replay.js", ANIM + "\n"],
    ["./form.js", FORMJS + "\n"],
];
const hashes = {};
for (const [path, body] of emitted) {
    const tmp = path + ".tmp";
    writeFileSync(tmp, body);
    const back = read(tmp);
    const want = sha(body);
    const got = sha(back);
    if (want !== got) {
        unlinkSync(tmp);
        throw new Error(`BUILD REFUSED — ${path} did not survive the round trip to disk`);
    }
    renameSync(tmp, path);
    if (sha(read(path)) !== want) {
        throw new Error(`BUILD REFUSED — ${path} changed between the rename and the re-read`);
    }
    hashes[path.replace("./", "")] = want;
    console.log(`wrote ${path.padEnd(14)} ${body.length.toLocaleString().padStart(7)} bytes  sha256 ${want.slice(0, 16)}…`);
}

writeFileSync(
    "./records/build.json",
    JSON.stringify(
        {
            schema: "computedriven-build-v1",
            _comment:
                "Written by build-site.mjs at emit. launch-gate.mjs re-hashes each artifact and refuses if one does not match — which is how the gate knows it is reading THIS build's output rather than a survivor of a build that threw before it rewrote the file. Source hashes are recorded too, so a source edited after the emit is caught as well.",
            built_at: new Date().toISOString(),
            version: surface.version,
            shell_revision: surface.shell_revision,
            artifacts: hashes,
            sources: Object.fromEntries(
                ["./src/landing.html", "./src/shell.css", "./src/replay.js", "./src/form.js", "./records/surface.json"].map(
                    (p) => [p.replace("./", ""), sha(read(p))]
                )
            ),
        },
        null,
        2
    ) + "\n"
);
console.log("wrote records/build.json — the gate proves the artifact against these hashes");
