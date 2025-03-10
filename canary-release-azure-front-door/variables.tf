variable "resource_group_name" {
  type    = string
  default = "rg-canary-release"
}

variable "location" {
  type    = string
  default = "ukwest"
}

variable "vnet_name" {
  type    = string
  default = "vnet-canary-release"
}

variable "subnet_name" {
  type    = string
  default = "subnet-canary"
}

variable "address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "subnet_prefix" {
  type    = list(string)
  default = ["10.0.1.0/24"]
}

variable "stable_storage_account" {
  type    = string
  default = "stablecontentuk"
}

variable "canary_storage_account" {
  type    = string
  default = "canarycontentuk"
}

variable "front_door_name" {
  type    = string
  default = "frontdoor-canary-uk"
}
