#!/usr/bin/env bash
# Publish site/ (Nine's support + privacy pages) to Cloudflare Pages.
#
#   NINE_CONTACT_EMAIL=you@example.com site/deploy.sh
#
# Needs CLOUDFLARE_API_TOKEN (Account → Cloudflare Pages: Edit) and
# CLOUDFLARE_ACCOUNT_ID in the environment, or a prior `npx wrangler login`.
# The pages land at https://$PROJECT.pages.dev/{support,privacy} — the URLs in
# fastlane/metadata/en-US/{support_url,privacy_url}.txt.
set -euo pipefail
PROJECT="${NINE_PAGES_PROJECT:-nine-couch-sudoku}"
: "${NINE_CONTACT_EMAIL:?set NINE_CONTACT_EMAIL — the support address the pages publish}"
here="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp "$here"/*.html "$here"/*.css "$out"/
sed -i.bak "s/{{CONTACT_EMAIL}}/${NINE_CONTACT_EMAIL}/g" "$out"/*.html && rm -f "$out"/*.bak
if grep -l "{{" "$out"/*.html; then echo "unfilled placeholder above" >&2; exit 1; fi
npx --yes wrangler@4 pages project create "$PROJECT" --production-branch main 2>/dev/null || true
npx --yes wrangler@4 pages deploy "$out" --project-name "$PROJECT" --branch main --commit-dirty=true
echo "https://$PROJECT.pages.dev/support"
echo "https://$PROJECT.pages.dev/privacy"
