variable "resource_group_name" {
  description = "The name of the main resource group"
  type        = string
}

variable "location" {
  description = "The location of the resources"
  type        = string
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
}

variable "function_app_name" {
  description = "The name of the Function App"
  type        = string
}

variable "service_bus_connection_string" {
  description = "The connection string for the Service Bus namespace"
  type        = string
}
