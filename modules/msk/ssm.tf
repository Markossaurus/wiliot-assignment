# Published for the workloads, which mount it through the Secrets Store CSI driver.
resource "aws_ssm_parameter" "bootstrap_brokers" {
  name  = "/${module.msk.cluster_name}/bootstrap-brokers-sasl-iam"
  type  = "SecureString"
  value = module.msk.bootstrap_brokers_sasl_iam
}
