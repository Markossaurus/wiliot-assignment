# Published for the workloads, which mount them through the Secrets Store CSI driver.
resource "aws_ssm_parameter" "connection" {
  for_each = {
    address = module.rds.db_instance_address
    port    = tostring(module.rds.db_instance_port)
    db-name = module.rds.db_instance_name
  }

  name  = "/${module.rds.db_instance_identifier}/${each.key}"
  type  = "SecureString"
  value = each.value
}
