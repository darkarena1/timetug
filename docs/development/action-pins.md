# GitHub Actions pins

Resolved from each action's official GitHub tag ref on 2026-09-26 with `gh api repos/OWNER/REPO/git/ref/tags/TAG --jq '.object.sha'`. Workflow `uses` entries retain the selected tag as a comment. Dependabot's `github-actions` weekly updates remain configured in `.github/dependabot.yml`.

| Action | Selected tag | Verified commit |
|---|---|---|
| `actions/checkout` | `v7` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/checkout` | `v4` | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/cache` | `v6` | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/upload-artifact` | `v7` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `FirebaseExtended/action-hosting-deploy` | `v0` | `7c850a480ce753f4f06f010801fc5a43787740bb` |

These are frozen commits, so release updates require an explicit pin change. The Firebase action runs only on the merge workflow, which still uses the existing service account. The PR website workflow has no deployment credentials.
