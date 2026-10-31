locals {
  suffix = "${var.region}-${var.env}"

  # namespace:name of each IRSA service account; must match charts/, argocd/kustomizations and the KEDA chart.
  service_accounts = {
    producer          = "trades:producer"
    producer_backfill = "trades:producer-backfill"
    consumer          = "trades:consumer"
    db_bootstrap      = "trades:db-bootstrap"
    data_probe        = "trades:data-probe"
    keda              = "keda:keda-operator"
    argocd            = "argocd:ecr-credentials"
  }

  # The SecureString parameters use the AWS-managed aws/ssm key; decrypting is allowed only through SSM.
  decrypt_parameters = {
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
    condition = [{
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }]
  }
}
