#!/usr/bin/env bash
# Builds the storefront for one environment and publishes it to S3 + CloudFront.
#
#   bash scripts/deploy-storefront.sh <environment>
#
# Optional environment variables: AWS_REGION (default ap-south-1), PROJECT (default
# looksmatter), UI_DIR (default ../looksmatter_ui next to this folder).
# Needs: AWS CLI, Node.js/npm.
set -euo pipefail

environment="${1:?usage: bash scripts/deploy-storefront.sh <environment>}"
region="${AWS_REGION:-ap-south-1}"
project="${PROJECT:-looksmatter}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ui_dir="${UI_DIR:-$script_dir/../../looksmatter_ui}"

# Where to publish comes from the infrastructure stack's contract parameter.
# MSYS_NO_PATHCONV stops Git Bash on Windows from turning "/looksmatter/..." into a file path.
contract="$(MSYS_NO_PATHCONV=1 aws ssm get-parameter --region "$region" \
  --name "/$project/$environment/infrastructure" --query Parameter.Value --output text)"

field() {
  node -e 'const c = JSON.parse(process.argv[1]); const v = c[process.argv[2]]; if (v == null) process.exit(1); console.log(String(v));' "$contract" "$1"
}

bucket="$(field storefront_bucket)" || { echo "Storefront hosting is turned off for $environment." >&2; exit 1; }
distribution="$(field storefront_distribution_id)"
api_domain="$(field api_domain)"
first_domain="$(field storefront_domains | cut -d, -f1)"

echo "→ building the storefront against https://$api_domain/api"
(
  cd "$ui_dir"
  npm ci
  VITE_API_BASE_URL="https://$api_domain/api" npm run build
)

# Vite puts fingerprinted files (the name changes whenever the content does) in
# dist/assets, so browsers may cache them for a year. Everything else, above all
# index.html, must be revalidated so shoppers get a new release immediately.
aws s3 sync "$ui_dir/dist/assets" "s3://$bucket/assets" \
  --region "$region" --cache-control "public,max-age=31536000,immutable" --only-show-errors

aws s3 sync "$ui_dir/dist" "s3://$bucket" \
  --region "$region" --exclude "assets/*" --exclude "_redirects" \
  --cache-control "public,max-age=0,must-revalidate" --delete --only-show-errors

# Old fingerprinted assets stay in the bucket on purpose: browsers that still have the
# previous index.html open keep working until they reload.
MSYS_NO_PATHCONV=1 aws cloudfront create-invalidation --distribution-id "$distribution" \
  --paths "/*" --query Invalidation.Id --output text >/dev/null

echo "✓ Published: https://$first_domain"
