output "function_app_id" {
  description = "The ID of the Function App"
  value       = azurerm_linux_function_app.function_app.id
}

output "function_app_identity_principal_id" {
  description = "The principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.function_app.identity[0].principal_id
}
