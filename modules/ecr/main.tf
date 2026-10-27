module "ecr" {
  source   = "terraform-aws-modules/ecr/aws"
  version  = "3.2.0"
  for_each = toset(var.repositories)

  repository_name                 = each.value
  repository_image_tag_mutability = "IMMUTABLE"
  repository_image_scan_on_push   = true
  # Lets destroy delete repositories that still contain images.
  repository_force_delete = true

  # Same-account push and pull are authorized by IAM, so no repository policy is needed.
  create_repository_policy = false
  attach_repository_policy = false

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
