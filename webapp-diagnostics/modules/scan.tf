resource "azurerm_resource_group" "main_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "storage_account" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main_rg.name
  location                 = azurerm_resource_group.main_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container1" {
  name                  = "screenshots"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "container2" {
  name                  = "performace-profiles"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "container3" {
  name                  = "har-container"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "container4" {
  name                  = "memory-dump"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_service_plan" "asp" {
  name                = "function-app-service-plan"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "function_app" {
  name                       = var.function_app_name
  location                   = azurerm_resource_group.main_rg.location
  resource_group_name        = azurerm_resource_group.main_rg.name
  service_plan_id            = azurerm_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key

  identity {
    type = "SystemAssigned"
  }
  site_config {}
}

resource "azurerm_role_assignment" "storage_role" {
  principal_id         = azurerm_linux_function_app.function_app.identity[0].principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.storage_account.id
}
