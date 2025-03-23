variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "UK West"
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.50"
    }
  }
  required_version = ">= 1.3.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "ghost" {
  name     = "ghost-blog-rg"
  location = var.location
}

resource "azurerm_virtual_network" "ghost" {
  name                = "ghost-vnet-clean"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.ghost.name
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres-subnet-clean"
  resource_group_name  = azurerm_resource_group.ghost.name
  virtual_network_name = azurerm_virtual_network.ghost.name
  address_prefixes     = ["10.0.4.0/24"]
  delegation {
    name = "fsDelegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "aca_clean" {
  name                 = "aca-subnet-clean2"
  resource_group_name  = azurerm_resource_group.ghost.name
  virtual_network_name = azurerm_virtual_network.ghost.name
  address_prefixes     = ["10.0.250.0/23"]
}

resource "azurerm_postgresql_flexible_server" "ghost" {
  name                          = "ghostpgserver"
  resource_group_name           = azurerm_resource_group.ghost.name
  location                      = var.location
  version                       = "13"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.pg.id
  administrator_login           = "ghostadmin"
  administrator_password        = "GhostPassword123!" # change this securely in production
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  public_network_access_enabled = false
}

resource "azurerm_private_dns_zone" "pg" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.ghost.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "pg" {
  name                  = "pg-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.pg.name
  resource_group_name   = azurerm_resource_group.ghost.name
  virtual_network_id    = azurerm_virtual_network.ghost.id
}

resource "azurerm_container_app_environment" "ghost_env" {
  name                           = "ghost-env2"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.ghost.name
  internal_load_balancer_enabled = false
  infrastructure_subnet_id       = azurerm_subnet.aca_clean.id
}

resource "azurerm_container_app" "ghost" {
  name                         = "ghost-blog"
  container_app_environment_id = azurerm_container_app_environment.ghost_env.id
  resource_group_name          = azurerm_resource_group.ghost.name
  revision_mode                = "Single"

  template {
    container {
      name   = "ghost"
      image  = "ghost:latest"
      cpu    = 0.5
      memory = "1.0Gi"

      env {
        name  = "database__client"
        value = "postgres"
      }

      env {
        name  = "database__connection__host"
        value = "${azurerm_postgresql_flexible_server.ghost.name}.postgres.database.azure.com"
      }

      env {
        name  = "database__connection__user"
        value = "ghostadmin"
      }

      env {
        name  = "database__connection__password"
        value = "GhostPassword123!"
      }

      env {
        name  = "database__connection__database"
        value = "ghost"
      }

      env {
        name  = "url"
        value = "https://your-domain.com"
      }
    }
  }

  ingress {
    external_enabled = false
    target_port      = 2368
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

output "container_app_url" {
  value = azurerm_container_app.ghost.latest_revision_fqdn
}

