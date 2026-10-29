#!/usr/bin/env bash
# Launches the one-shot bootstrap instance and waits for the result its script prints to the console.
set -euo pipefail

template_id=$1
template_version=$2
region=$3
deadline=$((SECONDS + 1500))

instance_id=$(aws ec2 run-instances --region "$region" \
  --launch-template "LaunchTemplateId=$template_id,Version=$template_version" \
  --query 'Instances[0].InstanceId' --output text)
echo "Launched Argo CD bootstrap instance $instance_id"

console_output() {
  # --latest only works while the instance runs; afterwards, fall back to the buffered output.
  aws ec2 get-console-output --region "$region" --instance-id "$instance_id" --latest --query Output --output text 2>/dev/null ||
    aws ec2 get-console-output --region "$region" --instance-id "$instance_id" --query Output --output text
}

output=""
while ((SECONDS < deadline)); do
  sleep 15
  output=$(console_output || true)
  case "$output" in
    *ARGOCD_BOOTSTRAP_RESULT=success*)
      echo "Argo CD bootstrap succeeded on $instance_id"
      exit 0
      ;;
    *ARGOCD_BOOTSTRAP_RESULT=failure*)
      echo "Argo CD bootstrap failed on $instance_id. Last console lines:" >&2
      tail -n 60 <<<"$output" >&2
      exit 1
      ;;
  esac
done

echo "Timed out waiting for the Argo CD bootstrap; terminating $instance_id. Last console lines:" >&2
tail -n 60 <<<"$output" >&2
aws ec2 terminate-instances --region "$region" --instance-ids "$instance_id" >/dev/null
exit 1
