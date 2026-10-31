locals {
  suffix = "${var.region}-${var.env}"
  name   = "argocd-bootstrap-${local.suffix}"

  # Written by hand rather than with `aws eks update-kubeconfig`, so the role needs no IAM permissions.
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name    = var.cluster_name
      cluster = { server = var.cluster_endpoint, certificate-authority-data = var.cluster_certificate_authority_data }
    }]
    users = [{
      name = "bootstrap"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", data.aws_region.current.region]
        }
      }
    }]
    contexts        = [{ name = "bootstrap", context = { cluster = var.cluster_name, user = "bootstrap" } }]
    current-context = "bootstrap"
  })
}

# Launched once per cluster by terraform_data.bootstrap; the instance terminates itself when the
# script finishes, so nothing is left running or billed.
resource "aws_launch_template" "bootstrap" {
  name                                 = "lt-${local.name}"
  image_id                             = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = "terminate"

  user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    kubectl_version         = var.kubectl.version
    kubectl_sha256          = var.kubectl.sha256
    helm_version            = var.helm.version
    helm_sha256             = var.helm.sha256
    argocd_chart_repository = var.argocd_chart_repository
    argocd_chart_version    = var.argocd_chart_version
    kubeconfig              = local.kubeconfig
    argocd_values           = var.argocd_values
    root_application        = var.root_application
  }))

  iam_instance_profile {
    arn = module.iam_role.instance_profile_arn
  }

  network_interfaces {
    subnet_id                   = var.subnet_id
    security_groups             = [module.security_group.id]
    associate_public_ip_address = false
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Provider default tags don't reach resources that RunInstances creates from a template.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(data.aws_default_tags.current.tags, { Name = "ec2-${local.name}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(data.aws_default_tags.current.tags, { Name = "ebs-${local.name}" })
  }

  lifecycle {
    # A newer AL2023 AMI would otherwise create a template version on every apply.
    ignore_changes = [image_id]
  }
}
