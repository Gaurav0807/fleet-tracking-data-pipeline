resource "aws_ecr_repository" "dbt_runner" {
  name                 = "${local.prefix}-dbt-runner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# Build and push Docker image automatically after ECR repo is created
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.dbt_runner]

  # Rebuild when any of these files change
  triggers = {
    dockerfile   = filemd5("${path.module}/../dbt_project/Dockerfile")
    handler      = filemd5("${path.module}/../dbt_project/handler.py")
    dbt_project  = filemd5("${path.module}/../dbt_project/dbt_project.yml")
    profiles     = filemd5("${path.module}/../dbt_project/profiles.yml")
    packages     = filemd5("${path.module}/../dbt_project/packages.yml")
    models       = sha1(join("", [for f in sort(fileset("${path.module}/../dbt_project/models", "**/*")) : filemd5("${path.module}/../dbt_project/models/${f}")]))
    macros       = sha1(join("", [for f in sort(fileset("${path.module}/../dbt_project/macros", "**/*")) : filemd5("${path.module}/../dbt_project/macros/${f}")]))
  }

  provisioner "local-exec" {
    environment = {
      DOCKER_BUILDKIT = "0"
    }
    command = <<-EOT
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
      docker build --platform linux/amd64 -t ${local.prefix}-dbt-runner ${path.module}/../dbt_project
      docker tag ${local.prefix}-dbt-runner:latest ${aws_ecr_repository.dbt_runner.repository_url}:latest
      docker push ${aws_ecr_repository.dbt_runner.repository_url}:latest
    EOT
  }
}
