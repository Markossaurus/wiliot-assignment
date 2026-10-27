# Root Terragrunt configuration, included by every unit under live/.
# Defines the remote state backend, the AWS provider and inputs shared by all units.

locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  region  = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals

  # The sandbox only allows IAM roles, policies and S3 buckets named with this prefix.
  name_prefix = "mark-tatarinov"

  region_parts = split("-", local.region.aws_region)
  region_short = "${local.region_parts[0]}${substr(local.region_parts[1], 0, 1)}${local.region_parts[2]}"
}

# The assignment requires Terraform; without this Terragrunt prefers OpenTofu when both are installed.
terraform_binary = "terraform"
# 1.10 is the first release with S3-native state locking (use_lockfile below).
terraform_version_constraint = ">= 1.10"

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  # The bucket is pre-created by the sandbox and lives in eu-central-1 regardless of which region
  # a unit deploys to. Locking uses an S3 lock object; the sandbox's DynamoDB lock table is
  # unused because Terraform deprecated dynamodb_table in favour of use_lockfile.
  config = {
    bucket       = "${local.name_prefix}-tfstate-${local.account.account_id}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region              = "${local.region.aws_region}"
      allowed_account_ids = ["${local.account.account_id}"]

      default_tags {
        tags = {
          Project     = "binance-trades"
          Environment = "${local.account.env}"
          ManagedBy   = "terragrunt"
          # Repo-relative path of the unit that owns the resource, e.g. live/prod/eu-central-1/vpc.
          ModulePath  = "${get_path_from_repo_root()}"
          # The sandbox keys IAM permissions off this tag, and it separates resources
          # from other candidates' in the shared account.
          candidate   = "${local.name_prefix}"
        }
      }
    }
  EOF
}

inputs = {
  env                       = local.account.env
  region                    = local.region_short
  name_prefix               = local.name_prefix
  permissions_boundary_name = "CandidateBoundary"
}
