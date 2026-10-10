"""Checks security and coverage invariants that shell syntax validation cannot see."""
from pathlib import Path
import re
import sys
import yaml

root = Path(__file__).resolve().parents[3]
workflows = {}
errors = []
for path in sorted((root / '.github/workflows').glob('*.yml')):
    document = yaml.safe_load(path.read_text())
    workflows[path.name] = document
    for name, job in document['jobs'].items():
        for step in job.get('steps', []):
            action = step.get('uses')
            if action and not re.fullmatch(r'[^@]+@[0-9a-f]{40}', action):
                errors.append(f'{path.name}/{name}: action is not pinned: {action}')

pr = workflows['firebase-hosting-pull-request.yml']
for name in ('ci.yml', 'firebase-hosting-pull-request.yml'):
    pr_text = (root / '.github/workflows' / name).read_text()
    # The one exception (docs/superpowers/specs/2026-10-09-windows-program-design.md, section 8): ci.yml may read the
    # read-only Docker Hub pull token, which fork PRs never receive. Every other secret stays out of PR workflows.
    allowed_secrets = {'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN'} if name == 'ci.yml' else set()
    used_secrets = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', pr_text))
    if 'pull_request_target' in pr_text or used_secrets - allowed_secrets or 'firebaseServiceAccount' in pr_text:
        errors.append(f'{name}: PR-triggered workflow must not use pull_request_target or secrets')
if pr.get('permissions') != {'contents': 'read'}:
    errors.append('PR website workflow must have read-only contents permission')
if not any('verify.sh release-tools' in step.get('run', '') for job in pr['jobs'].values() for step in job['steps']):
    errors.append('PR website workflow does not validate the website')
pr_runs = '\n'.join(step.get('run', '') for job in pr['jobs'].values() for step in job['steps'])
if 'requirements-test.txt' not in pr_runs:
    errors.append('PR website workflow does not install pinned test prerequisites')
if 'build/verify-venv/bin:$PATH' not in pr_runs:
    errors.append('PR website workflow does not use pinned test prerequisites')

ci = workflows['ci.yml']
tooling = ci['jobs'].get('release-tooling')
if tooling is None:
    errors.append('CI missing release-tooling job')
else:
    runs = '\n'.join(step.get('run', '') for step in tooling['steps'])
    if 'scripts/dev/verify.sh release-tools' not in runs:
        errors.append('CI release-tooling job does not use verify.sh release-tools')
    if 'requirements-test.txt' not in runs:
        errors.append('CI release-tooling job does not install pinned prerequisites')
    if 'build/verify-venv/bin:$PATH' not in runs:
        errors.append('CI release-tooling job does not use pinned prerequisites')

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

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: workflow contracts')
