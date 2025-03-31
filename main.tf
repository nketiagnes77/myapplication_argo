resource "azurerm_resource_group" "aks-ag" {
  name     = "aks-rg"
  location = "East US"
}

resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "aks-identity"
  resource_group_name = azurerm_resource_group.aks-ag.name
  location            = azurerm_resource_group.aks-ag.location
}

resource "azurerm_public_ip" "ingress_ip" {
  name                = "ingress-ip"
  location            = azurerm_resource_group.aks-ag.location
  resource_group_name = azurerm_resource_group.aks-ag.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_kubernetes_cluster" "aks-ag" {
  name                = "aks-ag"
  resource_group_name = azurerm_resource_group.aks-ag.name
  location            = azurerm_resource_group.aks-ag.location
  dns_prefix          = "aks-rgdns"

  default_node_pool {
    name                         = "default"
    node_count                   = 2
    vm_size                      = "Standard_D2_v2"
    temporary_name_for_rotation  = "tempdefault"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks-ag.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks-ag.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks-ag.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600
  wait             = true

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.ingress_ip.ip_address
  }
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }
  set {
    name  = "controller.admissionWebhooks.timeoutSeconds"
    value = "30"
  }
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks-ag
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600
  wait             = true

  values = [
    <<EOF
server:
  service:
    type: LoadBalancer
EOF
  ]

  depends_on = [
    azurerm_kubernetes_cluster.aks-ag
  ]
}

resource "kubernetes_ingress_v1" "argocd_ingress" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "argocd.example.com"  # Replace with your domain or use the external IP
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }
  depends_on = [
    helm_release.nginx_ingress,
    helm_release.argocd
  ]
}

output "ingress_ip" {
  value = azurerm_public_ip.ingress_ip.ip_address
}
