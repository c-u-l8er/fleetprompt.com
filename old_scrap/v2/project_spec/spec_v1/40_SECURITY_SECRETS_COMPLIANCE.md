# fleetprompt.com — Security, Secrets, and Compliance (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **FleetPrompt v1** security posture: threat model, mitigations, secrets strategy, UGC safety, and compliance-oriented constraints.

FleetPrompt is **Layer 5** (marketplace/distribution) in the portfolio:
- It is **public-facing** and therefore **high-risk** for abuse and UGC attacks.
- It is **reference-first** and MUST NOT execute agents/workflows or mirror upstream runtime logs/telemetry.
- It provides an **install handoff** (intent + token) that MUST NOT become an auth bypass into other systems.

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Security objectives (what we protect)

### 1.1 Primary assets
FleetPrompt must protect:
- **Tenant isolation / ownership boundaries**
  - publisher A cannot mutate publisher B’s listings/releases
  - buyer A cannot read buyer B’s install intents/tokens
- **Install handoff integrity**
  - install tokens cannot be forged, replayed indefinitely, or redeemed by browsers
- **User accounts and sessions**
  - account takeover resistance (baseline)
- **UGC rendering safety**
  - prevent XSS, phishing surfaces, and malicious links/embeds
- **Operational integrity**
  - prevent spam, scraping, upload abuse, and denial-of-service
- **Secret material**
  - prevent leakage of platform secrets, internal service secrets, or token-like values

### 1.2 Security goals (v1)
FleetPrompt v1 MUST:
1. Enforce **IDOR-safe** access control on every private resource.
2. Ensure **install tokens are short-lived, revocable, and non-reusable** (single-use recommended).
3. Prevent **XSS** and unsafe content rendering for listings and release notes.
4. Implement **anti-abuse controls** appropriate for a public marketplace.
5. Avoid **secrets in logs** and avoid storing plaintext secrets at rest.
6. Maintain a minimal **audit trail** for security-relevant actions.

### 1.3 Explicit security boundaries (hard rules)
FleetPrompt MUST NOT:
- Execute WHS agents or Agentromatic workflows.
- Proxy privileged actions into WHS/Agentromatic/Agentelic as the user from the browser.
- Treat “purchase/ownership” as authorization to install/execute (commerce is SpecPrompt; auth is owning system).
- Store or mirror upstream execution logs, telemetry streams, or transcripts.

FleetPrompt MAY:
- Store bounded, secret-free metadata and references (opaque IDs).
- Provide server-to-server redemption resolution for install tokens.

---

## 2) Threat model (practical)

### 2.1 Actors
- **Anonymous attacker** (no account): scraping, spam, UGC probing, XSS attempts, DoS.
- **Authenticated attacker** (normal account): malicious listings/releases, install token abuse, probing IDOR.
- **Publisher attacker**: malicious releases, phishing listings, attempting to attack other publishers.
- **Insider/admin**: misuse of moderation/suspension powers.
- **Compromised downstream system**: attempts to redeem tokens improperly or at high volume.
- **Supply chain attacker**: malicious dependencies, CI compromise, asset upload poisoning.

### 2.2 Attack surfaces (non-exhaustive)
- Public listing pages (rendering user-generated markdown/content).
- Search endpoints (query parsing, CPU/DB abuse, scraping).
- Publisher console mutations (listing create/update, release publish).
- Artifact/image upload endpoints (if present in v1).
- Install intent/token issuance endpoints.
- Internal server-to-server redemption endpoints (`/v1/internal/...`).
- Logging/analytics (secret and token leakage risk).
- Moderation tooling (privileged actions).

### 2.3 Required mitigations (v1)
Mitigations are organized by threat.

#### T1: Cross-tenant access (IDOR)
Risks:
- A user guesses IDs to read or mutate another tenant’s listing, release, install intent, or token state.

Mitigations (MUST):
- Every private read/write MUST enforce ownership:
  - publisher resources: `publisherUserId == callerUserId`
  - buyer resources: `buyerUserId == callerUserId`
- Cross-tenant IDs MUST return **NOT_FOUND** (recommended) to reduce existence oracle leaks.
- Never accept `publisherId`/`buyerUserId` from client as the scope selector; scope is derived from auth.

#### T2: Unauthorized listing/release mutation
Risks:
- A non-publisher creates or publishes listings.
- A publisher modifies a listing they don’t own.
- Mass updates via automated abuse.

Mitigations (MUST):
- Publisher capability gating (role/flag) is required for publisher write endpoints.
- Ownership checks are required for every mutation.
- Rate limits on create/update/publish endpoints.
- Idempotency on retryable writes to avoid duplicate state transitions under retries.

#### T3: Install handoff confused deputy (FleetPrompt becomes a proxy)
Risks:
- Browser clients call internal redeem endpoints to force installs.
- Tokens used to bypass downstream authorization checks.
- Replay of tokens to repeatedly trigger installs or imports.

Mitigations (MUST):
- Internal redemption endpoints MUST be server-to-server authenticated and MUST reject browser-originated calls:
  - deny CORS; do not allow wildcard origins
  - require a server auth scheme (HMAC over raw bytes or mTLS recommended)
- Install token redemption MUST NOT itself perform install side effects.
  - Redemption resolves references and intent only.
  - Target system redeems and must enforce its own authz (membership/ownership/roles) before installing.
- Tokens MUST be:
  - opaque
  - short-lived
  - revocable
  - preferably single-use
- Token material MUST NOT contain secrets or unbounded content.

#### T4: Secret leakage (tokens, internal headers, logs)
Risks:
- Install tokens appear in logs, analytics, error messages, or client-visible payloads.
- Internal server-to-server auth secrets leak.

Mitigations (MUST):
- Never log raw install tokens or internal auth headers.
- Store tokens as:
  - hash (preferred), or
  - opaque random token that is only resolvable server-side
- Error messages must be safe and never include:
  - token values
  - internal auth material
  - raw upstream payloads
- Strict redaction in logging for common secret-like keys:
  - `authorization`, `cookie`, `token`, `apiKey`, `secret`, `password`, `signature`

#### T5: XSS and unsafe rendering (UGC)
Risks:
- Listing description or release notes inject HTML/JS.
- Markdown links used for phishing.
- Image metadata or SVG injects script.
- Stored XSS affects publishers/admins.

Mitigations (MUST):
- Do not render raw HTML from user content.
- If markdown is supported:
  - sanitize to a safe subset (no raw HTML, no scriptable protocols)
  - escape output properly
- Enforce link policy:
  - allow only `https:` links (recommended)
  - add `rel="noopener noreferrer nofollow"` to external links
  - optionally add `target="_blank"` only with noopener (avoid tabnabbing)
- Restrict images:
  - if allowing external image URLs, proxy them or allowlist domains (recommended: do not hotlink arbitrary domains in v1)
  - forbid SVG uploads unless sanitized with a robust, well-understood sanitizer (recommended: forbid SVG in v1)
- Implement Content Security Policy (CSP) in the web app:
  - default deny scripts from untrusted origins
  - disallow inline scripts if possible
- Sanitize and bound user-provided display names and bios.

#### T6: Abuse / DoS / scraping
Risks:
- Search endpoint hammered (scraping).
- Listing pages scraped at scale.
- Publisher endpoints spammed.
- Token endpoints brute-forced.

Mitigations (SHOULD; MUST if public Internet):
- Rate limit:
  - public search/list endpoints (IP-based + user-based where possible)
  - listing detail endpoints (IP-based)
  - publisher mutations
  - install intent creation and token issuance
  - internal redeem endpoint (service-level quotas)
- Enforce pagination limits and cursor usage; cap `limit`.
- Add basic bot mitigation at the CDN/edge layer (if available).
- Detect and block high-error-rate clients (temporary bans).

#### T7: Open redirects and URL injection
Risks:
- `docsUrl`, `repoUrl`, image URLs used to inject `javascript:` or redirect loops.

Mitigations (MUST):
- Validate URLs strictly:
  - allow schemes: `https:` only (recommended)
  - enforce max length
  - reject control characters and whitespace
- If using redirect endpoints, enforce allowlists and signed redirects.

#### T8: Upload poisoning (if uploads exist in v1)
Risks:
- Malware uploads, zip bombs, huge files, content-type spoofing.

Mitigations (MUST if uploads are implemented):
- Enforce strict file size limits.
- Enforce allowed MIME types (server-side sniffing, not just client headers).
- Store and verify file hashes (sha256).
- Virus scan and/or sandbox validation (if feasible).
- Strip metadata (EXIF) from images (recommended).
- Never serve uploads from the same origin without strong content-type and CSP protections.

#### T9: Moderation misuse / insider risk
Risks:
- Admin can suspend listings without audit or with hidden reasons.

Mitigations (MUST):
- Admin actions MUST be audited (append-only).
- Moderation reasons MUST be bounded and must not contain secrets.
- Keep a clear public/private split:
  - public sees “suspended/unavailable”
  - publisher sees a safe reason (optional) without revealing reporter identities

---

## 3) Authentication and identity

### 3.1 Auth provider (recommended)
Use a shared portfolio identity provider (e.g., stable external subject id). FleetPrompt MUST:
- resolve `externalId` → internal `users` row server-side
- never trust client-supplied identity fields

### 3.2 Session security (baseline)
- Use secure cookies or bearer JWT with proper expiry.
- Protect against CSRF if using cookies (CSRF tokens / same-site cookies).
- Enforce TLS everywhere.

### 3.3 Account takeover mitigations (v1 baseline)
If FleetPrompt runs its own auth:
- rate limit login attempts
- password policy and secure hashing
- optional MFA later

If FleetPrompt uses an external IdP:
- rely on IdP for MFA; still rate limit sensitive actions.

---

## 4) Authorization and access control (tenant isolation)

### 4.1 Tenant model (v1 baseline)
- Publisher ownership is user-scoped in v1:
  - listings/releases owned by `publisherUserId`
- Buyer ownership is user-scoped in v1:
  - install intents/tokens owned by `buyerUserId`

### 4.2 Required authorization checks (patterns)
Every private endpoint MUST:
1. authenticate caller
2. resolve caller to internal user id
3. fetch resource by id
4. enforce `resource.owner == callerUserId`
5. return `NOT_FOUND` if not visible (recommended)

### 4.3 No silent privilege widening
- A user is not a publisher unless explicitly granted publisher capability.
- Verification badges do not grant permissions.
- “Install token exists” does not grant permission to install; downstream systems must re-check.

---

## 5) Secrets strategy (normative)

### 5.1 Core rule (MUST)
FleetPrompt MUST NOT store plaintext secrets in its database or logs, including:
- API keys, OAuth tokens
- internal service credentials
- install token raw values (except transiently at issuance time; store only hash or opaque lookup id)

### 5.2 Token handling (install tokens)
Install token requirements:
- Opaque token strings generated server-side with sufficient entropy.
- Store only:
  - token hash (recommended), or
  - token id mapping (opaque random id) where raw token never persists.
- Token TTL MUST be short by default (10–60 minutes recommended).
- Token redemption MUST be single-use by default:
  - first redemption transitions token to `redeemed`
  - subsequent redemptions return `NOT_FOUND` (recommended) to reduce token enumeration.
- Issuing a new token MAY revoke previous tokens for the same intent (recommended).

Token values MUST:
- never be included in error messages
- never be logged
- never be sent to analytics providers

### 5.3 Internal server-to-server authentication (internal endpoints)
For `/v1/internal/*` endpoints, FleetPrompt MUST use a server-auth mechanism that is not usable from browsers.

Acceptable patterns:
- HMAC signature over raw body bytes + timestamp window (recommended if aligning with portfolio patterns)
- mTLS between services (recommended)
- Private network + short-lived service JWT (acceptable if implemented correctly)

Requirements (MUST):
- include replay protection (timestamp skew window at minimum)
- reject missing/invalid signatures
- rate limit internal endpoints and log failures safely

### 5.4 Redaction requirements
All logs and error responses MUST be safe:
- redact secret-like keys
- truncate large payloads
- avoid logging raw request bodies for sensitive endpoints

---

## 6) UGC safety requirements (mandatory)

### 6.1 Allowed content formats
FleetPrompt SHOULD use a constrained markdown subset for:
- listing descriptions
- release notes
- publisher bios

FleetPrompt MUST:
- sanitize markdown output before rendering
- strip or disallow raw HTML
- escape output in templates/components

### 6.2 Link and embed policy
- Only allow `https:` links (recommended).
- Add `rel="noopener noreferrer nofollow"` to outbound links.
- Consider adding a warning interstitial for external links (optional v1).
- Do not embed arbitrary third-party iframes/scripts.

### 6.3 Images policy (v1)
Recommended v1 stance:
- Avoid arbitrary third-party image hotlinking.
- If images are allowed:
  - store in your controlled object storage/CDN
  - restrict MIME types (jpeg/png/webp/gif recommended)
  - forbid SVG in v1
  - enforce size limits and strip metadata

### 6.4 Search safety
- Do not use unbounded regex or expensive parsing on user-controlled `q` values.
- Normalize and bound search input lengths.
- Apply rate limits for search.

---

## 7) Logging, auditability, and evidence

### 7.1 Audit events (recommended baseline)
FleetPrompt SHOULD maintain an append-only audit log for:
- listing created/updated/status-changed
- release published/revoked
- install intent created
- install token issued/revoked/redeemed
- admin suspension/moderation actions

Audit records MUST be:
- immutable (append-only)
- bounded
- secret-free

### 7.2 Correlation
All requests SHOULD have a `requestId`.
- Include `requestId` in normalized error envelopes.
- Use it to correlate:
  - token issuance → redemption attempts → downstream acknowledgements (if implemented later)

### 7.3 Safe error reporting
- Use normalized errors (per API contract).
- Do not leak:
  - whether a token exists
  - whether a resource exists cross-tenant
  - internal exception messages that contain sensitive details

---

## 8) Data handling, privacy, and retention

### 8.1 Data minimization (required)
FleetPrompt should store only what it needs:
- public listing metadata
- publisher profile metadata (bounded)
- install intents and tokens (short-lived)
- minimal audit logs

FleetPrompt MUST NOT:
- store user secrets
- store upstream runtime logs/telemetry/transcripts

### 8.2 PII handling (assume it exists)
PII likely includes:
- email (if stored)
- display name
- IP addresses (in logs, if captured)
- purchase metadata (but commerce is SpecPrompt)

Requirements:
- Avoid exposing PII publicly.
- Minimize PII in logs; hash IPs if you need them for rate limiting analytics.
- Provide a plan for deletion/anonymization later (v1 can be “documented but deferred”).

### 8.3 Retention (v1 defaults; adjust before production)
Recommended starting defaults:
- Install tokens: retain 30 days after expiration/redemption for audit, then purge.
- Install intents: retain 90 days (or longer if needed for support).
- Audit logs: retain at least 90 days (security operations) and longer if needed.

---

## 9) Compliance posture (v1)
FleetPrompt v1 is not “certified” by default. Treat compliance as “good hygiene”:
- follow least privilege
- maintain audit trails
- minimize stored data

### 9.1 Content moderation / takedown (recommended)
Because FleetPrompt is UGC-heavy, v1 SHOULD include:
- a way to suspend/takedown listings (admin)
- a minimal reporting mechanism (optional)
- audit logs for moderation actions

### 9.2 Legal/financial boundaries
- FleetPrompt is not the payment processor; commerce is SpecPrompt.
- Do not store payment instrument details in FleetPrompt.

---

## 10) Security testing checklist (v1)

### 10.1 Tenant isolation / IDOR (MUST)
- Attempt to access another publisher’s listing via publisher endpoints returns `NOT_FOUND`.
- Attempt to revoke another publisher’s release returns `NOT_FOUND`.
- Attempt to read another buyer’s install intent/token state returns `NOT_FOUND`.
- Public endpoints never return drafts/unlisted listings.

### 10.2 XSS (MUST)
- Stored XSS attempts in markdown are neutralized (no script execution).
- Links cannot use `javascript:` or other unsafe schemes.
- No raw HTML rendering from UGC.

### 10.3 Token security (MUST)
- Tokens are short-lived and expire as expected.
- Token values are not logged (verify via log search).
- Token replay is denied if single-use.
- Token enumeration is mitigated (invalid token returns `NOT_FOUND` recommended).

### 10.4 Internal endpoint hardening (MUST)
- Internal redemption endpoints reject browser calls:
  - CORS denies
  - missing signature denies
- Replay protection works (timestamp window).
- Rate limiting exists for internal endpoints.

### 10.5 Abuse controls (SHOULD; MUST if public)
- Search rate limits prevent scraping at scale.
- Publisher mutation endpoints rate-limited.
- Install token issuance endpoints rate-limited.

### 10.6 Secrets leakage (MUST)
- No secret-like values appear in:
  - logs
  - error envelopes
  - persisted records
- Verify redaction on common headers and fields.

---

## 11) Security acceptance criteria (Definition of Done)
FleetPrompt v1 is security-complete when:
1. **Tenant isolation is proven**
   - an automated IDOR suite demonstrates cross-tenant access is blocked across all private endpoints.
2. **UGC rendering is safe**
   - stored XSS attempts do not execute; markdown is sanitized; link policy enforced.
3. **Install handoff is not a confused deputy**
   - internal redemption is server-to-server only
   - tokens are short-lived, revocable, preferably single-use
   - redemption does not itself perform side effects; it only resolves intent and references
4. **No secrets leakage**
   - secrets and tokens do not appear in logs/errors/analytics
5. **Abuse controls exist**
   - rate limiting and pagination caps prevent trivial scraping/DoS
6. **Auditability exists**
   - security-relevant actions produce append-only audit events with safe summaries

---