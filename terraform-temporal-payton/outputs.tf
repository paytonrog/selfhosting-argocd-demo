output "aws_profile" {
  value = var.aws_profile
}

output "region" {
  value = var.region
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --profile ${var.aws_profile}"
}

output "rds_endpoint" {
  value = aws_db_instance.temporal.endpoint
}

output "rds_proxy_endpoint" {
  value = aws_db_proxy.temporal.endpoint
}

output "temporal_namespace" {
  value = var.temporal_namespace
}

output "temporal_ui_access" {
  value = "Internal only. Use: kubectl -n ${var.temporal_namespace} port-forward svc/temporal-web 8080:8080"
}

output "argocd_namespace" {
  value = var.argocd_namespace
}

output "argocd_ui_access" {
  value = "Internal only. Use: kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8081:443"
}

output "argocd_initial_admin_password_command" {
  value = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode; echo"
}