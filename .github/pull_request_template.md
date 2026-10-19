<!--
Thank you for your contribution! Please fill out the sections below so reviewers have everything they need.
-->

**Issue #, if available:**

**Description of changes:**

**Verification:**
<!-- e.g. deployed the webapp via webapp/deploy.sh and ran the T104 query, `agentcore status` showing the new image, etc. -->

**Checklist:**
- [ ] `requirements.txt` regenerated if runtime deps changed (`uv export --no-hashes --no-dev --no-editable -o requirements.txt`)
- [ ] README updated if user-facing behavior changed
- [ ] No secrets, account IDs, or ARNs in the diff (`git diff main..HEAD | grep -E '([0-9]{12}|aws_access_key|pat_token)'`)

---

By submitting this pull request, I confirm that my contribution is made under the terms of the MIT-0 license.
