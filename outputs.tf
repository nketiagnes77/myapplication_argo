output "configcommand" {
    value = "az aks get-credentials --resource-group aks-rg --name aks-ag"
  
}
# Output Commands to Retrieve ArgoCD Access Info
output "config_command" {
  value = "az aks get-credentials --resource-group aks-rg --name aks-ag"
}

output "argocd_admin_password" {
  value     = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d"
  sensitive = true
}

output "argocd_url" {
  value = "kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
# Output Static IP
output "ingress_static_ip" {
  value = azurerm_public_ip.ingress_ip.ip_address
}

