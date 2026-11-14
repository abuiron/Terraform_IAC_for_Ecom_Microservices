#!/usr/bin/env bash
# Builds the three backend images and pushes them to Amazon ECR, all with the same tag.
#
#   bash scripts/build-and-push.sh           tag = current commit of ../looksmatter-backend
#   bash scripts/build-and-push.sh v1.4.0    explicit tag
#
# Optional environment variables: AWS_REGION (default ap-south-1), PROJECT (default
# looksmatter), BACKEND_DIR (default ../looksmatter-backend next to this folder).
set -euo pipefail

region="${AWS_REGION:-ap-south-1}"
project="${PROJECT:-looksmatter}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backend_dir="${BACKEND_DIR:-$script_dir/../../looksmatter-backend}"

if [ "$#" -ge 1 ]; then
  tag="$1"
else
  # The tag is the commit id, so the code must actually be committed.
  if [ -n "$(git -C "$backend_dir" status --porcelain)" ]; then
    echo "The backend has uncommitted changes, so a commit id would not describe the image." >&2
    echo "Commit first, or pass an explicit tag: bash scripts/build-and-push.sh <tag>" >&2
    exit 1
  fi
  tag="$(git -C "$backend_dir" rev-parse --short=12 HEAD)"
fi

account_id="$(aws sts get-caller-identity --query Account --output text)"
registry="$account_id.dkr.ecr.$region.amazonaws.com"

aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"

context_for() {
  case "$1" in
    gateway) echo "gateway" ;;
    core-service) echo "services/core-service" ;;
    order-service) echo "services/order-service" ;;
  esac
}

for service in gateway core-service order-service; do
  repository="$project/$service"
  image="$registry/$repository:$tag"

  # Tags are immutable in ECR: if this one exists, it already holds this commit's image.
  if aws ecr describe-images --region "$region" --repository-name "$repository" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
    echo "✓ $image already exists, skipping"
    continue
  fi

  echo "→ building $image"
  # linux/amd64 matches the cluster's nodes, even when building on an Apple Silicon Mac.
  docker build --platform linux/amd64 --tag "$image" "$backend_dir/$(context_for "$service")"
  docker push "$image"
done

echo
echo "Pushed tag: $tag"
echo "Deploy it:  bash scripts/tf.sh <environment> workloads apply -var image_tag=$tag"
