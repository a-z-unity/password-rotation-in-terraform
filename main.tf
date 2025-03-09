provider "azurerm" {
  features {}
}

provider "random" {}

provider "time" {}

resource "time_rotating" "postgresql_flexible_server_login_password_rotating" {
  rotation_days = 1
}

resource "random_password" "postgresql_flexible_server_login" {
  length  = 32
  special = false
  keepers = {
    rotation_time = time_rotating.postgresql_flexible_server_login_password_rotating.id
  }
}

resource "random_password" "postgresql_flexible_server_password" {
  length           = 32
  special          = true
  override_special = "!#*()-_+[]{}<>"
  keepers = {
    rotation_time = time_rotating.postgresql_flexible_server_login_password_rotating.id
  }
}

resource "azurerm_resource_group" "default" {
  name     = "password-rotation-in-terraform-rg"
  location = "West Europe"
}

resource "azurerm_postgresql_flexible_server" "default" {
  name                   = "password-rotation-in-terraform-pgsql"
  resource_group_name    = azurerm_resource_group.default.name
  location               = azurerm_resource_group.default.location
  version                = "16"
  administrator_login    = "l${random_password.postgresql_flexible_server_login.result}"
  administrator_password = random_password.postgresql_flexible_server_password.result
  sku_name               = "B_Standard_B1ms"
  lifecycle {
    ignore_changes = [
      zone, high_availability.0.standby_availability_zone
    ]
  }
}