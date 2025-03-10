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

# Create Resource Group in UK West
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create Virtual Network (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  address_space       = var.address_space
}

# Create Subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_prefix
}

# Stable Content Storage Account (Without Static Website)
resource "azurerm_storage_account" "stable" {
  name                     = var.stable_storage_account
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Canary Content Storage Account (Without Static Website)
resource "azurerm_storage_account" "canary" {
  name                     = var.canary_storage_account
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create Containers in Both Storage Accounts for Content
resource "azurerm_storage_container" "stable_container" {
  name                  = "content"
  storage_account_name  = var.stable_storage_account
  container_access_type = "container"
}

resource "azurerm_storage_container" "canary_container" {
  name                  = "content"
  storage_account_name  = var.canary_storage_account
  container_access_type = "container"
}

# Stable Backend (80% Traffic)
resource "azurerm_cdn_frontdoor_origin" "stable" {
  name                           = "stable-backend"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.origin_group.id
  enabled                        = true
  host_name                      = "${azurerm_storage_account.stable.name}.blob.core.windows.net"
  weight                         = 80
  priority                       = 1
  origin_host_header             = "${azurerm_storage_account.stable.name}.blob.core.windows.net"
  certificate_name_check_enabled = true
}

# Canary Backend (20% Traffic)
resource "azurerm_cdn_frontdoor_origin" "canary" {
  name                           = "canary-backend"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.origin_group.id
  enabled                        = true
  host_name                      = "${azurerm_storage_account.canary.name}.blob.core.windows.net"
  weight                         = 20
  origin_host_header             = "${azurerm_storage_account.canary.name}.blob.core.windows.net"
  certificate_name_check_enabled = true
}


# Create Private Endpoints for Stable Storage
resource "azurerm_private_endpoint" "stable_endpoint" {
  name                = "stable-private-endpoint"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "stable-private-connection"
    private_connection_resource_id = azurerm_storage_account.stable.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_endpoint" "canary_endpoint" {
  name                = "canary-private-endpoint"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "canary-private-connection"
    private_connection_resource_id = azurerm_storage_account.canary.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

# Create Managed Identity for Front Door
resource "azurerm_user_assigned_identity" "frontdoor_identity" {
  name                = "frontdoor-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Assign Storage Blob Data Reader Role to Front Door
resource "azurerm_role_assignment" "frontdoor_blob_role_stable" {
  scope                = azurerm_storage_account.stable.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.frontdoor_identity.principal_id
}

resource "azurerm_role_assignment" "frontdoor_blob_role_canary" {
  scope                = azurerm_storage_account.canary.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.frontdoor_identity.principal_id
}

resource "azurerm_cdn_frontdoor_profile" "frontdoor" {
  name                = var.front_door_name
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "fd_endpoint" {
  name                     = "canary-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id
}

# Backend Pool (Stable & Canary)
resource "azurerm_cdn_frontdoor_origin_group" "origin_group" {
  name                     = "origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id
  session_affinity_enabled = true
  load_balancing {
    additional_latency_in_milliseconds = 50
  }
}

# Routing Rule for Azure Front Door
resource "azurerm_cdn_frontdoor_route" "route" {
  name                          = "canary-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.fd_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin_group.id
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.stable.id,
    azurerm_cdn_frontdoor_origin.canary.id
  ]
  supported_protocols = ["Http", "Https"]
  patterns_to_match   = ["/*"]
  forwarding_protocol = "MatchRequest"
}


# 7. Create a Rule to Set ARRAffinity Cookie for Session Stickiness
resource "azurerm_cdn_frontdoor_rule_set" "canary" {
  name                     = "canaryruleset"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id
}

resource "azurerm_cdn_frontdoor_rule" "enable_session_affinity" {
  name                      = "enablesessionaffinity"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.canary.id
  order                     = 1
  conditions {

  }
  actions {
    response_header_action {
      header_action = "Append"
      header_name   = "ARRAffinity"
      value         = "True"
    }
  }
}
