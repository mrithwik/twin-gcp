# Digital Twin on Vercel + Cloud Run — Decisions & Walkthrough

This document has two parts:

1. **[Decisions](#part-1-decisions)** — every major architectural choice made in this project, what the alternatives were, and why this option won.
2. **[Walkthrough](#part-2-walkthrough)** — a start-to-finish narrative of everything that was actually built and done, in order, written for someone who has never seen this project before.

---

# Part 1: Decisions

## 1.1 Why a separate repo instead of modifying the AWS version in place?

**Chosen:** A brand-new repo (`twin-gcp`), fresh git history, sibling to the original `twin` repo.

**Alternatives considered:**
- Modify `twin` in place to swap AWS for GCP/Vercel.
- Add a branch in `twin` for the alternate stack.

**Why this won:** The goal is a **portfolio**, not a migration. Two live, working, differently-architected deployments of the same product is a stronger portfolio artifact than one deployment that replaced the other — it shows the same problem solved on two clouds, which is a more interesting story in an interview than "I moved my app from AWS to GCP." Modifying in place would destroy the AWS version's value as a separate demonstration of Terraform + Lambda + Bedrock + CloudFront skills.

## 1.2 Why Vercel + Cloud Run instead of an all-in-one platform?

**Chosen:** Vercel (frontend) + Google Cloud Run (backend), two separate platforms.

**Alternatives considered:**
- **Vercel alone** (Next.js frontend + Python serverless functions in the same project). Simpler — one platform, one deploy command.
- **Cloud Run for everything**, including a Next.js container.

**Why this won:** This is explicitly a **portfolio project** meant to demonstrate breadth to recruiters/hiring managers, not the simplest possible way to run a chatbot. A split architecture shows:
- Real containerization (a `Dockerfile`, not a framework auto-wrapping your code)
- A genuine service boundary with a documented API contract between two independently-deployed pieces
- Multi-cloud competence (GCP IAM/Terraform alongside Vercel)

The tradeoff, stated explicitly rather than hidden: two platforms to configure/monitor instead of one, and Cloud Run's scale-to-zero means occasional cold-start latency on infrequent traffic. Acceptable for a demo; not a good tradeoff for, say, a startup MVP where shipping speed matters more than the demo value of the architecture.

## 1.3 Why a monolith backend, not microservices (unlike the `prodigon` reference repo)?

**Chosen:** One FastAPI service, internally organized into modules (`routes/`, `services/`, `config.py`, `errors.py`).

**Alternatives considered:** Split into `api_gateway` / `model_service` / `worker_service`, mirroring `prodigon`'s teaching architecture.

**Why this won:** `prodigon` is a *teaching* codebase whose whole purpose is demonstrating microservices patterns — the complexity is the point. This app is a single-user chatbot with one synchronous request type (chat) and no background job processing. Splitting it into three deployed services would mean three times the IaC, three times the deploy pipelines, and inter-service network calls for no actual capability gained. "Knowing when *not* to add microservices" is itself something worth demonstrating — over-architecting a simple problem is a real anti-pattern interviewers watch for.

What *was* borrowed from `prodigon`, because it's good practice regardless of service topology:
- Typed, env-driven config via `pydantic-settings` (`app/config.py`)
- A typed exception hierarchy so every error returns the same JSON shape (`app/errors.py`)
- Route logic separated from app wiring (`app/routes/`)
- A real test suite with the external dependency (Gemini) mocked out (`tests/`)

## 1.4 Why Google Gemini instead of Bedrock, Groq, or OpenAI?

**Chosen:** Gemini, via the `google-genai` SDK.

**Alternatives considered:**
- **Keep Bedrock** — not possible for free; Bedrock is AWS-only and this stack has no AWS dependency by design.
- **Groq** — what `prodigon` uses; fast, generous free tier, but it's a third external vendor on top of Vercel + GCP.
- **OpenAI** — the original backend already had an `OPENAI_API_KEY` var wired in from an earlier experiment, so it required no re-plumbing, but OpenAI's free tier is trial-credit-only, not a standing free tier.

**Why this won:** Gemini keeps the "cloud story" coherent — Cloud Run and Gemini are both Google products, so the pitch is "GCP end-to-end" rather than "GCP, plus a third-party AI vendor, plus Vercel." It also has a genuine standing free tier (see §1.7 below for the important gotcha this caused).

## 1.5a Reliability follow-up: is Gemini's free tier actually prudent to depend on?

After getting Gemini working end-to-end (§2.12–2.14 below), a fair question came up: the setup process hit enough friction (billing-tier confusion, a deprecated model ID, a transient `503`) that it was worth pausing to ask whether depending on Gemini's free tier was the right call at all, rather than just pushing through and moving on.

**The options considered:**

- **A. Stay on Gemini, harden the code against transient failures** — add retry-with-backoff around the API call, so a `503`/`429` resolves automatically instead of requiring a manual re-request.
- **B. Switch to Groq** — `prodigon`'s provider; free tier is less entangled with GCP billing concepts, so likely less setup friction. Tradeoff: breaks the "GCP end-to-end" story and adds a third vendor; Groq has its own failure mode (per-minute rate limits) rather than being strictly more reliable.
- **C. Switch to OpenAI** — already ruled out earlier (§1.4): free tier is trial-credit only, not standing.
- **D. Multi-provider fallback** (Gemini primary, a second provider as backup) — most robust, but doubles the API surface (two SDKs, two keys, fallback branching logic) for a single-user demo chatbot. The same over-engineering concern as §1.3 (monolith vs. microservices) applies here.

**Why A won:** The friction actually broke down into two different categories. The billing-tier confusion, the wrong billing project, and the deprecated model ID were all **one-time setup mistakes**, now fixed and not expected to recur. The `503 high demand` error is a fundamentally different thing: a transient capacity issue that is a normal, ongoing characteristic of calling *any* hosted LLM API — Groq, OpenAI, and Anthropic's own API all have moments of this. Switching providers (B) would not eliminate this class of failure, it would just change which specific transient errors show up occasionally. Given that, the fix that actually addresses "this takes multiple tries" is retry logic in the code — proportionate, provider-agnostic, and it's the same fix you'd want to add no matter which provider had been chosen.

**What was implemented:** `app/services/gemini_client.py` now retries automatically (up to 3 attempts, with a short exponential backoff) specifically on the error codes that are genuinely transient (`429`, `500`, `503`). Errors that retrying can't fix — a bad API key, an unknown model ID, a malformed request — are raised immediately on the first attempt, since retrying those would just waste time and hide a real configuration problem behind a delay. Tests (`tests/test_gemini_client.py`) cover all three paths: a transient error that resolves on retry, one that exhausts all retries and correctly surfaces as an `InferenceError`, and a non-transient error that is correctly *not* retried.

## 1.5 Why Firestore instead of Cloud Storage (GCS) for conversation memory?

**Chosen:** Firestore, one document per `session_id` in a `conversations` collection.

**Alternatives considered:** Replicate the AWS version's approach exactly — GCS bucket, one JSON blob per session, `get_object`/`put_object`.

**Why this won:** The AWS version used S3 because that's what was already there, not because S3/GCS is a good fit for structured, frequently-read-and-updated JSON records. Firestore is a native document database — reading/writing a session's message list is a single `.get()`/`.set()` call with no manual JSON serialization-to-blob dance, and it has its own generous free tier (1 GiB storage, 50k reads + 20k writes/day). This is a case where porting the *pattern* (swap the memory backend behind an interface) mattered more than porting the *exact implementation*.

## 1.6 Why local Terraform state, not a remote GCS backend (unlike the AWS repo's S3 + DynamoDB setup)?

**Chosen:** Local `terraform.tfstate`, git-ignored, single `prod`-equivalent environment (no dev/test/prod workspaces).

**Alternatives considered:** Mirror the AWS repo exactly — remote state bucket, state locking table, three Terraform workspaces.

**Why this won:** Remote state + locking exists to solve *team* problems (two people applying at once, needing a durable state store independent of anyone's laptop) and *multi-environment* problems (promoting the same config through dev → test → prod). This is a single-maintainer personal project with one deployed environment. Building the remote-state bootstrap (which itself has a chicken-and-egg problem — see the AWS repo's own two-step apply process for its state bucket) would be infrastructure serving a team-of-one, over-engineering in the same spirit as §1.3's microservices decision.

## 1.7 Why Workload Identity Federation instead of a downloaded service account key?

**Chosen:** WIF — GitHub Actions authenticates to GCP by presenting its own OIDC token, which GCP trusts based on a configured trust policy (repo name, in this case), with no long-lived secret ever stored in GitHub.

**Alternatives considered:** Create a GCP service account key (a JSON file with permanent credentials), store it as a GitHub secret, use it directly in the workflow.

**Why this won:** A downloaded key is a long-lived credential that works forever until manually rotated or revoked — if it leaks, whoever has it has standing access. WIF tokens are short-lived and scoped to the specific run of a specific workflow in a specific repo. This is the same reasoning behind the AWS repo's GitHub Actions OIDC setup — deliberately keeping that "no long-lived credentials" story consistent across both cloud versions was a specific design goal, not a coincidence.

## 1.8 The `output: 'export'` decision (a bug fix that's really an architecture decision)

The original frontend's `next.config.ts` had `output: 'export'`, which makes `next build` produce a folder of static HTML/CSS/JS files instead of a deployable server. That was necessary for the **AWS** version because S3 + CloudFront can only serve static files — there's no server behind them to run Next.js's SSR features.

Vercel is a **native Next.js host** — it runs the framework directly, with full support for server-side rendering, API routes, etc. Forcing a static export on Vercel is not just unnecessary, it turned out to be actively broken (see §2.9 in the walkthrough) with this Next.js version's newer static-export file format. Removing `output: 'export'` was the correct fix, not a workaround — the constraint that required it (a static-files-only host) no longer applies.

## 1.9 Why `gemini-flash-latest` instead of a specific dated model like `gemini-2.5-flash`?

**Chosen:** The `-latest` alias, which Google keeps pointed at their current recommended flash-tier model.

**Why this won:** This project directly hit the failure mode this avoids — see §2.11. A dated model ID can be deprecated for new API keys/projects without warning, breaking a deployed app with no code change on your part. The alias trades a small amount of reproducibility (you don't know exactly which model version you're calling on any given day) for resilience against exactly the kind of breakage this project experienced. For a portfolio demo where "the chat still works when someone clicks the link in six months" matters more than pinning an exact model version, that trade is worth it.

---

# Part 2: Walkthrough

This section retells, in order, everything that was actually done — as if explaining it to someone who has never seen a cloud deployment before.

## 2.1 Starting point

There was already a working app (`twin`, a separate repo): a Next.js frontend and a single-file FastAPI backend, deployed on AWS (Lambda + API Gateway + Bedrock for the AI + S3 for storing conversation history), managed with Terraform and deployed via GitHub Actions. The ask was: rebuild the same app on a different, free-tier stack, as a second portfolio piece, without touching the AWS version.

## 2.2 Researching the target architecture

Before writing any code, the existing `twin` repo and a second reference repo (`prodigon`, a teaching codebase demonstrating production system-design patterns with a proper microservices layout, typed config, tests, and architecture docs) were both read in full. This established what patterns were worth borrowing (see §1.3) versus what was overkill for this project's actual scope.

## 2.3 Choosing the stack

A short back-and-forth established: Vercel for the frontend, Google Cloud Run for the backend, Gemini for the AI, Firestore for conversation memory, and a brand-new sibling repo rather than modifying the AWS version. See Part 1 above for the reasoning behind each choice.

## 2.4 Scaffolding the new repo

A new directory, `/Users/mrithwik/projects/twin-gcp`, was created with its own fresh `git init` — deliberately *not* sharing history with the AWS repo, since the two projects' commit histories aren't meaningfully related once the architecture diverges this much. The reusable pieces were copied over as-is: the personal data files (`facts.json`, `style.txt`, `summary.txt` — the content that makes the chatbot "know" things about the person it represents) and the entire frontend (which needed almost no changes, since a chat UI that calls a REST API doesn't care much which cloud is behind that API).

## 2.5 Rebuilding the backend

The original backend was a handful of flat files (`server.py`, `context.py`, `resources.py`). It was restructured into a proper Python package:

- `app/config.py` — a `Settings` class (via `pydantic-settings`) that reads every configuration value from environment variables, with type validation, instead of scattered `os.getenv()` calls.
- `app/errors.py` — a small hierarchy of exception types (`AppError` → `ValidationError`, `InferenceError`, `ConversationNotFoundError`), each carrying an HTTP status code and a machine-readable error code, so every failure mode returns the same JSON shape: `{"error": {"code": "...", "message": "..."}}`.
- `app/schemas.py` — the request/response data shapes (`ChatRequest`, `ChatResponse`, etc.), using Pydantic for automatic validation.
- `app/prompt.py` — builds the system prompt that tells Gemini "you are acting as this specific person's digital twin," pulling in the data files from step 2.4.
- `app/services/gemini_client.py` — the only file that talks to the Gemini SDK directly. If the AI provider ever changes again, this is the one file that needs to change.
- `app/services/memory_store.py` — reads/writes conversation history, with two backends selected by a config flag: `local` (a JSON file on disk, for development) or `firestore` (for the real deployment).
- `app/routes/health.py` and `app/routes/chat.py` — the actual HTTP endpoints, kept thin (they call into `services/`, they don't contain business logic themselves).
- `app/main.py` — wires everything together: creates the FastAPI app, adds CORS middleware, registers a single exception handler for `AppError`, and mounts the routers.

## 2.6 Writing tests

A `tests/` directory was added — the original AWS version had none. `conftest.py` sets up a `TestClient` with the Gemini client **mocked out** (so tests never need a real API key or network access) and the memory backend pointed at a temporary directory. `test_chat.py` then exercises the actual behavior: a health check, a full chat round trip, conversation persistence across multiple messages, and the 404 behavior for an unknown session. All 4 tests were run and confirmed passing before moving on — a recurring theme throughout this project was **verifying each piece actually works before building the next thing on top of it**, rather than assuming code that "looks right" behaves correctly.

## 2.7 Containerizing the backend

A `Dockerfile` was written — a Python slim base image, the app code copied in, dependencies installed, and a `uvicorn` entrypoint that listens on whatever port Cloud Run assigns via the `$PORT` environment variable (Cloud Run injects this at runtime; hardcoding a port would break the deploy). This was built and actually run locally with `docker build`/`docker run` before anything touched real cloud infrastructure — confirming the health endpoint, the root endpoint, and that a request with a fake API key produced a clean, well-formatted error (rather than a crash) instead of just assuming the Dockerfile was correct.

## 2.8 Writing the infrastructure as code (Terraform)

The Terraform configuration (`infra/terraform/`) declares everything the backend needs to run in GCP:
- **Artifact Registry** — a Docker image repository (Cloud Run's equivalent of Docker Hub, but private and GCP-native).
- **Cloud Run service** — the actual running backend, configured to accept public traffic.
- **Firestore** — the conversation-memory database.
- **Secret Manager** — holds the Gemini API key; Cloud Run reads it at runtime rather than having it baked into the container image or passed as a plain environment variable.
- **A runtime service account** — a least-privilege identity Cloud Run uses to access Firestore and the secret, with no broader permissions than that.
- **A GitHub Actions deploy identity**, trusted via Workload Identity Federation (see §1.7) rather than a downloaded key.

This was validated locally (`terraform init`/`validate`) before any real GCP project existed — catching syntax and schema errors for free, with zero cloud cost or risk.

## 2.9 Writing the GitHub Actions workflow

`.github/workflows/deploy-backend.yml` was written to: run the test suite, then (only if tests pass) authenticate to GCP via WIF, build the Docker image, push it to Artifact Registry, and deploy it to Cloud Run. It triggers on any push to `main` that touches `backend/**`, plus a manual trigger option.

## 2.10 Provisioning GCP for real

With the user's explicit go-ahead (creating real, billed cloud resources is the kind of action worth pausing to confirm rather than doing silently), a new dedicated GCP project was created — deliberately **not** reusing an existing project, to keep this app's IAM and resource footprint isolated. This hit a few real bumps worth recording as part of the story:

- The first chosen project ID was already taken globally (GCP project IDs are unique across *all* of GCP, not just one account) — solved by picking a more distinctive ID.
- Project creation then hit a transient `429` rate limit from Google's own API — solved by retrying (in the background, polling, rather than guessing at a fixed wait time).
- `terraform apply` initially failed to create the Cloud Run service with a generic "internal error" — this turned out to be a real, if transient, revision failure, and because Google's Terraform provider defaults new Cloud Run services to `deletion_protection = true`, Terraform then refused to replace the broken service until that flag was explicitly set to `false` in the config *and* the broken instance was deleted directly via `gcloud` (Terraform's protection check reads the live resource's protection flag at destroy time, not just the new desired config — a real quirk worth knowing about).

All 22 planned resources were eventually created successfully, and the public Cloud Run URL was confirmed reachable before moving on.

## 2.11 Deploying the frontend to Vercel — and a real bug

The frontend was linked to a new Vercel project and deployed. The first deploy returned an **HTTP 404 on the homepage** despite Vercel reporting the build as successful. Diagnosing this (rather than just retrying) revealed two separate problems:

1. `next.config.ts` still had `output: 'export'` from the AWS version — see §1.8 for why this was wrong for Vercel specifically, and fixing it (removing the line entirely) was the correct move, not a workaround.
2. Even after that fix, the site still 404'd. Inspecting the Vercel project settings revealed **Framework Preset: "Other"** instead of "Next.js" — because the project had been created via a blank `vercel project add` command rather than letting `vercel link` auto-detect the framework from the actual code. The fix was adding a `vercel.json` with `{"framework": "nextjs"}`, committed to the repo — a declarative, permanent fix rather than a one-off dashboard click, so this can never silently regress again.

After both fixes, the deployed site returned a real `200`, and the actual JavaScript bundle sent to browsers was inspected directly (extracting the Cloud Run URL string out of the minified output) to confirm the frontend really was wired to the right backend — not just "the page loads," but "the page loads *and* points at the correct API."

## 2.12 Wiring the real Gemini API key — three separate billing surprises

This step surfaced more real-world friction than any other part of the project, all worth understanding:

1. **A fake key first**, to prove the error-handling path worked (`INFERENCE_ERROR` with a clean message, not a crash) before any real credentials existed.
2. **The user's first real key returned `429`: "prepayment credits depleted."** This turned out to be a Google AI Studio billing-tier issue — once a Gemini API key's backing GCP project has *any* billing account linked, Gemini treats it as "Prepay Tier 1," which requires an actual funded balance, regardless of whether usage is within otherwise-free limits.
3. **A related but distinct confusion**: at one point the *GCP* project's billing was found disabled — the user had deliberately unlinked it, believing that was how to force "free tier" usage. This is a common and reasonable-sounding misconception worth stating plainly: **GCP's free tier is not billing-free, it's usage-free.** A billing account must be linked for Cloud Run/Firestore/etc. to function at all; you simply aren't charged as long as usage stays under Google's "Always Free" monthly quotas. Unlinking billing entirely doesn't cap you at the free tier — it just breaks everything. This was clarified and the billing account was relinked, with explicit confirmation from the user before doing so, since changing billing state is exactly the kind of action worth pausing on rather than assuming.
4. **The actual fix for the Gemini prepay issue**: since Cloud Run's project *needs* billing linked, but a Gemini key tied to that same project will always be forced into the paid prepay tier, the fix was creating the Gemini API key under a **separate, fresh GCP project with no billing account attached at all** — keeping it on Gemini's genuine free tier. The key itself doesn't need to live in the same project as the service calling it; Google attributes usage/billing to whichever project issued the key, not whichever server makes the HTTP request.

Throughout this whole sequence, the API key itself was never once pasted into the conversation — it was edited directly into the git-ignored `terraform.tfvars` file and applied locally, at the user's explicit request to keep the secret out of the chat transcript entirely.

## 2.13 A model deprecation, and a config-drift bug

Once billing was sorted, a new error appeared: `404 — gemini-2.5-flash is no longer available to new users`. Rather than guess at a replacement, the actual list of models available to that specific key was queried directly against Google's API (reading the key from the local `terraform.tfvars` file into a shell variable, so it never appeared in any command output) — revealing `gemini-flash-latest` as the right choice (see §1.9).

The first attempt to fix this used a quick `gcloud run services update --update-env-vars=...` command to patch the running service directly, to unblock testing fast. But the *next* `terraform apply` (for an unrelated change) then **silently reverted that fix** — because Terraform reconciles a Cloud Run service's *entire* container spec on every apply, and since the model ID env var had only ever been set out-of-band via `gcloud`, Terraform didn't know about it and removed it. The real fix was adding `GEMINI_MODEL_ID` as a properly Terraform-managed environment variable, so it can never again be silently dropped by a future `apply`. This is a general lesson about Infrastructure as Code: **any change made outside the IaC tool will eventually be erased by the IaC tool**, and the fix is always to bring the change *into* the config, not to keep patching around it.

## 2.14 A transient provider error, and confirming a real reply

After all of the above, a `503 — model experiencing high demand` appeared — a genuinely transient, temporary issue on Google's end, not a configuration problem. Rather than treating this as another bug to fix, it was correctly identified as "just retry," and a background polling loop retried the same request every 15 seconds until it succeeded. On the fifth attempt, Gemini returned a real, correctly-grounded reply — speaking in the first person as the digital twin, citing specific facts from `facts.json`, and returning a `session_id` for conversation continuity. This was the first genuine end-to-end proof the whole system worked, not just that each piece individually looked correct.

## 2.15 Pushing to GitHub and wiring CI/CD

The user created the GitHub repo manually and provided the URL. From there: the code was pushed, `github_repo` in `terraform.tfvars` was updated from a placeholder to the real `owner/repo` (re-running `terraform apply` so the Workload Identity Federation trust policy actually matches, since it's scoped to a specific repo name for security), and the four values GitHub Actions needs (`GCP_PROJECT_ID`, `GCP_REGION` as repository *variables*; `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT` as repository *secrets* — the distinction matters because the workflow doesn't declare an `environment:`, so environment-scoped secrets/variables would never be visible to it) were added via the GitHub UI.

Once wired, a push triggered the workflow automatically: tests ran, the image was built and pushed with a git-commit-SHA tag, and Cloud Run deployed it — confirmed by checking that the currently-serving revision's image tag matched the commit SHA, rather than the earlier manually-built `:manual` tag.

## 2.16 A last cleanup

The deployed health check reported `"environment": "development"` because no `ENVIRONMENT` variable had ever been set in Terraform — cosmetic, but worth fixing properly rather than leaving a stray default in a "production" deployment. Since this project deliberately has only one environment (§1.6), the fix was a hardcoded `ENVIRONMENT = "production"` value directly in `main.tf`, rather than introducing a variable for a distinction that doesn't otherwise exist in this project.

## 2.17 Hardening against transient Gemini errors

After everything above was working, it was worth stepping back and asking whether depending on a free-tier LLM API — which had already caused enough friction to need three separate rounds of debugging — was actually a sound choice, or whether that friction was a sign to switch providers. Working through that question (see §1.5a for the full reasoning) separated the problem into two categories: one-time setup mistakes (now fixed, not expected to recur) versus the `503 high demand` error, which is a normal, ongoing characteristic of calling *any* hosted LLM API, not something switching providers would eliminate. The proportionate fix was adding automatic retry-with-backoff around the Gemini call for the specific error codes that are genuinely transient (`429`, `500`, `503`), while letting non-transient errors (bad key, unknown model, malformed request) fail immediately rather than wasting time retrying something retrying can't fix. Three new tests were added to cover exactly these three paths, and the full suite (7 tests) was re-run and confirmed passing before considering the change done.

## 2.18 Where things stand

Two independently-deployed pieces, both live: the frontend on Vercel, the backend on Cloud Run, wired together, tested, provisioned entirely through Terraform, and deployed continuously through GitHub Actions with no long-lived cloud credentials stored anywhere. Alongside the AWS/Bedrock/Lambda version of the same app, this forms two portfolio-worthy demonstrations of the same product built two different, defensible ways.
