terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create Resource Group
resource "azurerm_resource_group" "ghost" {
  name     = "ghost-blog-rg"
  location = "UK West"
}

# Create Azure Storage Account
resource "azurerm_storage_account" "ghost_storage" {
  name                     = "ghoststorageacct"
  resource_group_name      = azurerm_resource_group.ghost.name
  location                 = azurerm_resource_group.ghost.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create Azure Blob Container for SQLite
resource "azurerm_storage_container" "ghost_sqlite" {
  name                  = "ghost-sqlite"
  storage_account_name  = azurerm_storage_account.ghost_storage.name
  container_access_type = "private"
}

# Generate a Shared Access Signature (SAS) for BlobFuse
data "azurerm_storage_account_sas" "blobfuse_sas" {
  connection_string = azurerm_storage_account.ghost_storage.primary_connection_string
  https_only        = true
  start             = timestamp()
  expiry            = timeadd(timestamp(), "8760h") # 1 Year SAS token

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    file  = false
    queue = false
    table = false
  }

  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = true
    process = false
    filter  = false
    tag     = false
  }
}

# Create Azure Container Apps Environment
resource "azurerm_container_app_environment" "ghost_env" {
  name                = "ghost-env"
  location            = azurerm_resource_group.ghost.location
  resource_group_name = azurerm_resource_group.ghost.name
}

# Deploy Ghost with SQLite and BlobFuse
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
      memory = "1Gi"

      env {
        name  = "database__client"
        value = "sqlite3"
      }
      env {
        name  = "database__connection__filename"
        value = "/var/lib/ghost/content/data/ghost.db"
      }
      env {
        name  = "BLOBFUSE_STORAGE_ACCOUNT"
        value = azurerm_storage_account.ghost_storage.name
      }
      env {
        name  = "BLOBFUSE_STORAGE_CONTAINER"
        value = azurerm_storage_container.ghost_sqlite.name
      }
      env {
        name  = "BLOBFUSE_STORAGE_SAS"
        value = data.azurerm_storage_account_sas.blobfuse_sas.sas
      }

    }
    volume {
      name         = "sqlite-storage"
      storage_type = "AzureBlob"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 2368
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# Output the default Azure domain
output "ghost_blog_url" {
  value = "https://${azurerm_container_app.ghost.latest_revision_fqdn}"
}
