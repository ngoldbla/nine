#!/usr/bin/env bash
# Publish site/ (Nine's support + privacy pages) to Cloudflare as a static-assets
# Worker — which is how it was first deployed (2026-10-13, from the dashboard).
#
#   NINE_CONTACT_EMAIL=you@example.com site/deploy.sh
#   NINE_CONTACT_EMAIL=you@example.com site/deploy.sh --build-only   # dist/ + zip, no upload
#
# Needs CLOUDFLARE_API_TOKEN (Account → Workers Scripts: Edit) and
# CLOUDFLARE_ACCOUNT_ID in the environment, or a prior `npx wrangler login`.
# The pages live at https://nine-sudoku.ngoldbla.workers.dev/{support,privacy} —
# the URLs in fastlane/metadata/en-US/{support,privacy,marketing}_url.txt.
set -euo pipefail
WORKER="${NINE_WORKER:-nine-sudoku}"
: "${NINE_CONTACT_EMAIL:?set NINE_CONTACT_EMAIL — the support address the pages publish}"
here="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp "$here"/*.html "$here"/*.css "$out"/
sed -i.bak "s/{{CONTACT_EMAIL}}/${NINE_CONTACT_EMAIL}/g" "$out"/*.html && rm -f "$out"/*.bak
if grep -l "{{" "$out"/*.html; then echo "unfilled placeholder above" >&2; exit 1; fi
if [ "${1:-}" = "--build-only" ]; then
  # For a dashboard upload (Workers & Pages → the nine-sudoku Worker → upload):
  # the filled-in folder plus a zip of it, beside this script, gitignored.
  rm -rf "$here/dist" "$here/nine-site.zip"
  cp -R "$out" "$here/dist"
  (cd "$here/dist" && zip -qr "$here/nine-site.zip" .)
  echo "$here/dist"; echo "$here/nine-site.zip"
  exit 0
fi
npx --yes wrangler@4 deploy --name "$WORKER" --assets "$out" --compatibility-date 2026-10-01
echo "https://$WORKER.ngoldbla.workers.dev/support"
echo "https://$WORKER.ngoldbla.workers.dev/privacy"
