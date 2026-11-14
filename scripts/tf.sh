#!/usr/bin/env bash
# Runs Terraform for one stack of one environment, with the right state file and variables.
#
#   bash scripts/tf.sh <environment> <stack> <terraform command> [args...]
#
#   bash scripts/tf.sh global     shared         plan
#   bash scripts/tf.sh production infrastructure plan
#   bash scripts/tf.sh production workloads      apply -var image_tag=3f2c1ab9d4e5
#
#   environment  global (only for the shared stack), staging, production, ...
#   stack        shared | infrastructure | database | platform | workloads
set -euo pipefail

if [ "$#" -lt 3 ]; then
  sed -n '2,11p' "$0"
  exit 1
fi

environment="$1"
stack="$2"
command="$3"
shift 3

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stack_dir="$root/stacks/$stack"
env_dir="$root/environments/$environment"

[ -d "$stack_dir" ] || { echo "Unknown stack '$stack'. Choose one of: $(ls "$root/stacks" | tr '\n' ' ')" >&2; exit 1; }
[ -d "$env_dir" ] || { echo "Unknown environment '$environment'. Choose one of: $(ls "$root/environments" | tr '\n' ' ')" >&2; exit 1; }

if [ "$stack" = "shared" ] && [ "$environment" != "global" ]; then
  echo "The shared stack is account-wide: run it with 'global' as the environment." >&2
  exit 1
fi
if [ "$stack" != "shared" ] && [ "$environment" = "global" ]; then
  echo "'global' is only for the shared stack." >&2
  exit 1
fi

if grep -q "REPLACE_WITH" "$env_dir/backend.s3.tfbackend"; then
  echo "Fill in environments/$environment/backend.s3.tfbackend first (see the bootstrap stack's outputs)." >&2
  exit 1
fi

# All environments share one folder per stack, so each environment gets its own Terraform
# data directory. Otherwise a `plan` for production could silently use staging's state.
export TF_DATA_DIR=".terraform/$environment"

# Relative to the stack folder: works the same in Git Bash on Windows, macOS and Linux.
backend_file="../../environments/$environment/backend.s3.tfbackend"
var_file="../../environments/$environment/$stack.tfvars"

cd "$stack_dir"

init() {
  terraform init -reconfigure \
    -backend-config="$backend_file" \
    -backend-config="key=$environment/$stack.tfstate" \
    "$@"
}

if [ "$command" = "init" ]; then
  init "$@"
  exit 0
fi

# First use of this environment for this stack: initialise automatically.
if [ ! -f "$TF_DATA_DIR/terraform.tfstate" ]; then
  init
fi

case "$command" in
  plan | apply | destroy | import | console | refresh)
    terraform "$command" -var-file="$var_file" "$@"
    ;;
  *)
    terraform "$command" "$@"
    ;;
esac
