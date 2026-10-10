# Phase A: Move the signing secrets into environments (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Update `docs/superpowers/plans/2026-10-09-windows-program-tracker.md` (Now and Session log) when a task finishes.

**Goal:** No signing, notarization, Sparkle or OAuth value is readable by a workflow run that is not deployed to a protected environment, and a test keeps it that way.

**Architecture:** Every job that reads a secret declares `environment:`. The owner creates the environments and enters the values; the code change only adds the `environment:` lines, a contract test that enforces them, and the documentation. An environment secret overrides a repository secret of the same name and falls back to it when missing, so the code change is safe to merge before any value is moved, and the repository-level copies are deleted last.

**Tech Stack:** GitHub Actions environments, `gh api`, the existing `scripts/ci/tests/check-workflow-contracts.py` and `test-workflows.sh`.

**Spec:** `docs/superpowers/specs/2026-10-09-windows-program-design.md`, section 8 (findings, controls, and the 2026-10-09 amendment for read-only CI tokens).

## Global Constraints

- Environment names: `beta` and `hosting` (automatic, deployment policy `master` only, no reviewer), `release` (owner reviewer, deployment policy `master` and `v*` tags, admin bypass off), `appstore` (deployment policy `master` and `v*` tags; **no reviewer**, by the owner's choice on 2026-10-09).
- Only `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` may be read outside an environment, and only in `ci.yml` (spec section 8 amendment).
- Secret values never appear in chat, in the repository, in logs or in a command line argument. The owner enters each with `gh secret set NAME --env <environment> < file` or the GitHub UI.
- Agents never create or edit environments, never set secrets, never merge. The owner runs the commands in Task 4.
- PRs go to `master`; the owner squash-merges. Attribution: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A job that has `environment:` but whose environment is missing or has no policy.** GitHub creates a missing environment on first use with no protection at all. The runbook creates the environments (with their branch policy) before the code change merges.
2. **`workflow_run` and tags.** `beta.yml` runs from `workflow_run` on `master`, so its deployment ref is `master`; `release.yml` and `appstore.yml` also run for `v*` tags. The policies in Task 4 must allow exactly those.
3. **Deleting the repository-level copies too early.** An environment that is missing a value falls back to the repository secret, so a missing value shows up as a working run until the copy is deleted. Task 5 verifies each environment before any deletion.
4. **The same secret name in two environments** (the Developer ID certificate is used by `beta` and `release`; the OAuth values by `beta`, `release` and `appstore`). Each environment needs its own copy; none is shared.
5. **A reviewer-less `appstore` environment is only safe while tags and `master` are owner-only** (organization rulesets, phase 0). Until then the repository has one writer, so this holds.

---

### Task 1: Contract test: a job that reads a secret must declare an environment (RED)

**Files:**
- Modify: `scripts/ci/tests/check-workflow-contracts.py`
- Test: `scripts/ci/tests/test-workflows.sh` (runs the contract script)

**Interfaces:**
- Produces: a check that fails with `FAIL: <file>/<job>: reads secrets.<NAME> but declares no environment` and a table `EXPECTED_ENVIRONMENTS` mapping workflow file to its environment.

- [ ] **Step 1: Add the check.** Append this block to `check-workflow-contracts.py` immediately before the final `if errors:`:

```python
# Secrets are only readable through a protected environment (spec section 8). The Docker Hub pull token is the one
# amended exception, and only in ci.yml.
ALLOWED_OUTSIDE_ENVIRONMENT = {'ci.yml': {'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN'}}
IGNORED_SECRETS = {'GITHUB_TOKEN'}
EXPECTED_ENVIRONMENTS = {
    'beta.yml': 'beta',
    'release.yml': 'release',
    'appstore.yml': 'appstore',
    'firebase-hosting-merge.yml': 'hosting',
}
for file_name, document in workflows.items():
    allowed = ALLOWED_OUTSIDE_ENVIRONMENT.get(file_name, set())
    for job_name, job in document['jobs'].items():
        used = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', yaml.safe_dump(job))) - IGNORED_SECRETS - allowed
        environment = job.get('environment')
        if used and not environment:
            errors.append(f'{file_name}/{job_name}: reads secrets.{sorted(used)[0]} but declares no environment')
        expected = EXPECTED_ENVIRONMENTS.get(file_name)
        if used and environment and expected and environment != expected:
            errors.append(f'{file_name}/{job_name}: environment is {environment!r}, expected {expected!r}')
```

- [ ] **Step 2: Run it and watch it fail.**

Run: `bash scripts/ci/tests/test-workflows.sh`
Expected: `FAIL: beta.yml/beta: reads secrets.MACOS_CERTIFICATE_P12_BASE64 but declares no environment` and `FAIL: firebase-hosting-merge.yml/build_and_deploy: reads secrets.FIREBASE_SERVICE_ACCOUNT_TIMETUG but declares no environment`, exit 1. `release.yml` and `appstore.yml` already declare theirs and must not appear.

- [ ] **Step 3: Commit.**

```bash
git add scripts/ci/tests/check-workflow-contracts.py
git commit -m "Test that every job reading a secret declares an environment

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: Declare the environments (GREEN)

**Files:**
- Modify: `.github/workflows/beta.yml` (job `beta`, after `runs-on: macos-26`)
- Modify: `.github/workflows/firebase-hosting-merge.yml` (job `build_and_deploy`, after `runs-on: ubuntu-latest`)

**Interfaces:**
- Consumes: the contract test from Task 1.
- Produces: `beta` and `hosting` environments referenced by name; the owner creates them in Task 4.

- [ ] **Step 1: beta.yml.** Change

```yaml
    runs-on: macos-26
    env:
      GH_TOKEN: ${{ github.token }}
```

to

```yaml
    runs-on: macos-26
    environment: beta
    env:
      GH_TOKEN: ${{ github.token }}
```

- [ ] **Step 2: firebase-hosting-merge.yml.** Change

```yaml
  build_and_deploy:
    runs-on: ubuntu-latest
    steps:
```

to

```yaml
  build_and_deploy:
    runs-on: ubuntu-latest
    environment: hosting
    steps:
```

- [ ] **Step 3: Run the test and watch it pass.**

Run: `bash scripts/ci/tests/test-workflows.sh`
Expected: `PASS: workflow contracts` and `PASS`, exit 0.

- [ ] **Step 4: Negative check.** Temporarily delete the `environment: beta` line, run the test, confirm it fails with the Task 1 message, restore the line with `git checkout -p` or by retyping it (do not `git checkout` the whole file). Run the test again and confirm `PASS`.

- [ ] **Step 5: Commit.**

```bash
git add .github/workflows/beta.yml .github/workflows/firebase-hosting-merge.yml
git commit -m "Run the beta and website deploy jobs in protected environments

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: Update the documentation

**Files:**
- Modify: `docs/release.md` (line 69, the section `## GitHub Actions secrets to add later` and the closing OAuth sentence near line 190)

**Interfaces:**
- Consumes: the environment names from the Global Constraints.

- [ ] **Step 1: Line 69.** Replace the sentence "`beta.yml` declares no environment, so these must be repository secrets (see Troubleshooting)." with: "`beta.yml` runs in the `beta` environment, so these must be `beta` environment secrets (see GitHub Actions secrets)."

- [ ] **Step 2: Rename and introduce the secrets section.** Change the heading to `## GitHub Actions secrets` and replace the first sentence ("Add these under Settings > Secrets and variables > Actions. ...") with:

```markdown
Every signing, notarization, Sparkle and OAuth value lives in a GitHub environment, never at repository or organization level (only the read-only Docker Hub pull token in `ci.yml` is a repository secret; see the program spec, section 8). Add each under Settings > Environments > the environment > Environment secrets, or with `gh secret set NAME --env <environment> < file`. A value a job needs must be in that job's own environment; environments do not share secrets.

| Environment | Runs | Policy |
| --- | --- | --- |
| `beta` | `beta.yml` | Deployment branch `master` only; no reviewer |
| `release` | `release.yml` | Branch `master` and tags `v*`; the owner must approve; admin bypass off |
| `appstore` | `appstore.yml` | Branch `master` and tags `v*`; no reviewer (owner's choice) |
| `hosting` | `firebase-hosting-merge.yml` | Deployment branch `master` only; no reviewer |

Signing and notarizing a release happens only when ALL six release values are set (the `release` job). Betas are never notarized: they need only `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID` and `SPARKLE_PRIVATE_KEY`, and skip when any of those four is missing.
```

- [ ] **Step 3: Closing sentence.** Replace "The Google and Microsoft OAuth client secrets are the repository secrets the other workflows already use." with: "The Google and Microsoft OAuth client values (`GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `MICROSOFT_OAUTH_CLIENT_ID`) are entered separately in each of `beta`, `release` and `appstore`, because each of those workflows reads them."

- [ ] **Step 4: Add the per-environment value list** at the end of that section:

```markdown
**What each environment holds**

- `beta`: `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `SPARKLE_PRIVATE_KEY`, `MACOS_PROVISIONING_PROFILE_BASE64`, `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `MICROSOFT_OAUTH_CLIENT_ID`
- `release`: the same eight, plus `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, `NOTARY_API_KEY_P8_BASE64`
- `appstore`: `APPSTORE_DISTRIBUTION_CERT_P12`, `APPSTORE_INSTALLER_CERT_P12`, `APPSTORE_CERT_PASSWORD`, `APPSTORE_APP_PROFILE`, `APPSTORE_WIDGET_PROFILE`, `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, plus `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `MICROSOFT_OAUTH_CLIENT_ID`
- `hosting`: `FIREBASE_SERVICE_ACCOUNT_TIMETUG`
```

- [ ] **Step 5: Verify and commit.**

Run: `grep -n "repository secret" docs/release.md`
Expected: only the sentence naming the Docker Hub exception, if any.

Run: `bash scripts/ci/tests/test-workflows.sh`
Expected: `PASS`.

```bash
git add docs/release.md
git commit -m "Document that signing and OAuth secrets live in environments

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Push and open the pull request** (title: "Run beta and website deploys in environments and test that secrets stay there"). Stop here: the owner runs Task 4, then Task 5.

### Task 4: Create the environments and enter the values (owner)

Run in the owner's own terminal, on the Mac, signed in to `gh` as `darkarena1`. Nothing here is run by an agent. Every command below is safe to run before the pull request merges, because a missing environment value falls back to the repository secret.

- [ ] **Step 1: Create `beta` and `hosting` with a `master`-only policy.**

```bash
for env in beta hosting; do
  echo '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
    | gh api -X PUT repos/darkarena1/timetug/environments/$env --input -
  echo '{"name":"master","type":"branch"}' \
    | gh api -X POST repos/darkarena1/timetug/environments/$env/deployment-branch-policies --input -
done
```

- [ ] **Step 2: Turn off admin bypass on `release`** (the PUT replaces the environment's settings, so the reviewer and policy are restated):

```bash
ME=$(gh api user --jq .id)
jq -n --argjson me "$ME" '{can_admins_bypass:false, reviewers:[{type:"User",id:$me}], deployment_branch_policy:{protected_branches:false,custom_branch_policies:true}}' \
  | gh api -X PUT repos/darkarena1/timetug/environments/release --input -
gh api repos/darkarena1/timetug/environments/release/deployment-branch-policies --jq '[.branch_policies[]|.name]'
```

Expected last line: `["master","v*"]`. If either is missing, add it with `echo '{"name":"v*","type":"tag"}' | gh api -X POST repos/darkarena1/timetug/environments/release/deployment-branch-policies --input -`.

- [ ] **Step 3: Enter the values.** For each name in the lists in `docs/release.md` ("What each environment holds"), use the source in the tracker's "Where each secret comes from" table. Keep every value in a temporary file with mode 600, set it, and delete the file:

```bash
gh secret set NAME --env beta < file
```

Base64 values are the file's `base64 -i <file>` output. Do the same per environment; the same value goes into each environment that lists it. The OAuth values come from the xcconfig files in `~/.config/timetug/` (do not print them; read them into the command with `sed` or `cut`, or paste into the GitHub UI).

- [ ] **Step 4: Confirm the names are present** (names only; GitHub never shows values):

```bash
for env in beta release appstore hosting; do echo "== $env"; gh secret list --env $env --repo darkarena1/timetug | awk '{print $1}'; done
```

Compare against the lists in `docs/release.md`.

### Task 5: Verify each environment, then delete the repository copies (owner, agent-assisted)

- [ ] **Step 1: Merge the pull request** (owner). Merging it triggers CI on `master` and then `Beta`, which now runs in the `beta` environment.

- [ ] **Step 2: Check the beta run used the environment.** In the Beta run's "Set up job" log, the line `Environment: beta` appears and the run signs a build. Ask an agent to confirm with:

```bash
gh run list --repo darkarena1/timetug --workflow Beta --limit 1 --json databaseId,conclusion
gh run view <id> --repo darkarena1/timetug --log | grep -i "environment"
```

- [ ] **Step 3: Check `hosting`.** Change any file under `site/` in a throwaway or normal PR and merge it, or accept the next real site change; confirm the deploy job shows `Environment: hosting` and succeeds. Until then keep `FIREBASE_SERVICE_ACCOUNT_TIMETUG` at repository level.

- [ ] **Step 4: Check `release` and `appstore`.** At the next real release (or a trial: Actions > App Store > Run workflow with `ref=master`, which uploads a build to App Store Connect without publishing), confirm each job shows its environment, signs, and the owner's approval prompt appears for `release`.

- [ ] **Step 5: Delete the repository-level copies** only for names whose environments have each passed a run:

```bash
for n in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_TEAM_ID MACOS_PROVISIONING_PROFILE_BASE64 \
         SPARKLE_PRIVATE_KEY NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID NOTARY_API_KEY_P8_BASE64 \
         GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET MICROSOFT_OAUTH_CLIENT_ID FIREBASE_SERVICE_ACCOUNT_TIMETUG; do
  gh secret delete "$n" --repo darkarena1/timetug
done
gh secret list --repo darkarena1/timetug | awk '{print $1}'
```

Expected last output: only `DOCKERHUB_TOKEN` and `DOCKERHUB_USERNAME`.

- [ ] **Step 6: Re-verify after deletion.** Re-run the Beta workflow (or merge the next change) and confirm it still signs. If it falls back to "Signing secrets are not set; skipping the beta", a value is missing from `beta`: add it and re-run.

- [ ] **Step 7: Update the tracker** (Phase A done, owner checklist items checked, Session log line) and open the final pull request.
