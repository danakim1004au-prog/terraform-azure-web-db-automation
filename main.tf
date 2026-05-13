terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
  resource_group_name  = "rg-tfstate"
  storage_account_name = "tfstatexxxx"
  container_name       = "tfstate"
  key                  = "prod.tfstate"
}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  common_tags = {
    Environment = "Dev"
    Project     = "Secure-2Tier-Project"
    Owner       = "DayoungKim"
  }
}



# Generate a random suffix to ensure globally unique Azure resource names.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create the main resource group for the secure two-tier Azure architecture.
resource "azurerm_resource_group" "rg" {
  name     = "rg-secure-2tier-dev"
  location = "Korea Central"

  tags = local.common_tags
}

# Create the virtual network that hosts the application and database network segments.
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-main"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  tags = local.common_tags
}

# Create a delegated subnet for Azure App Service VNet Integration.
# This subnet allows the Linux Web App to securely access private Azure resources.
resource "azurerm_subnet" "web_subnet" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "webapp-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  service_endpoints = [
    "Microsoft.Sql",
    "Microsoft.KeyVault"
  ]
}

# Create a separate subnet to represent the database tier in the network design.
resource "azurerm_subnet" "db_subnet" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create a Network Security Group for the web tier.
resource "azurerm_network_security_group" "web_nsg" {
  name                = "nsg-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow inbound HTTP traffic to demonstrate basic web access control.
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Associate the Network Security Group with the web subnet.
resource "azurerm_subnet_network_security_group_association" "web_assoc" {
  subnet_id                 = azurerm_subnet.web_subnet.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

# Create a Linux App Service Plan.
# The S1 tier is used because Free-tier App Service Plans do not support VNet Integration.
resource "azurerm_service_plan" "asp" {
  name                = "asp-web-dev"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "S1"

  tags = local.common_tags
}

# Create an Azure SQL Server for the database tier.
resource "azurerm_mssql_server" "sql" {
  name                         = "sql-server-2tier-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.db_admin_password

  tags = local.common_tags
}

# Create a basic Azure SQL Database for cost-efficient development testing.
resource "azurerm_mssql_database" "db" {
  name      = "db-app-dev"
  server_id = azurerm_mssql_server.sql.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
  sku_name  = "Basic"

  tags = local.common_tags
}

# Restrict SQL Server access to the delegated web subnet using a virtual network rule.
resource "azurerm_mssql_virtual_network_rule" "sql_vnet_rule" {
  name      = "sql-vnet-rule"
  server_id = azurerm_mssql_server.sql.id
  subnet_id = azurerm_subnet.web_subnet.id

  depends_on = [
    azurerm_subnet.web_subnet
  ]
}

# Retrieve information about the currently authenticated Azure identity.
data "azurerm_client_config" "current" {}

# Create an Azure Key Vault to securely store application secrets.
resource "azurerm_key_vault" "kv" {
  name                        = "kv-secure-${random_string.suffix.result}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enabled_for_disk_encryption = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  tags = local.common_tags
}

# Grant the current deployment identity permission to manage secrets in Key Vault.
resource "azurerm_key_vault_access_policy" "admin_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# Store the SQL administrator password as a Key Vault secret.
resource "azurerm_key_vault_secret" "sql_password" {
  name         = "sql-admin-password"
  value        = var.db_admin_password
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_key_vault_access_policy.admin_policy
  ]
}

# Create the Linux Web App and integrate it with the delegated web subnet.
# Application settings use Key Vault references instead of storing secrets directly in code.
resource "azurerm_linux_web_app" "webapp" {
  name                = "webapp-secure-2tier-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  virtual_network_subnet_id = azurerm_subnet.web_subnet.id

  site_config {
    always_on = true

    application_stack {
      php_version = "8.2"
    }
  }

  app_settings = {
    "DB_SERVER"   = azurerm_mssql_server.sql.fully_qualified_domain_name
    "DB_NAME"     = azurerm_mssql_database.db.name
    "DB_USER"     = azurerm_mssql_server.sql.administrator_login
    "DB_PASSWORD" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_password.versionless_id})"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Grant the Web App managed identity permission to read secrets from Key Vault.
resource "azurerm_key_vault_access_policy" "webapp_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.webapp.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Output the deployed Web App URL for quick portfolio verification.
output "webapp_url" {
  value       = "https://${azurerm_linux_web_app.webapp.default_hostname}"
  description = "The URL of the deployed Linux Web App."
}

# Output the Azure SQL Server FQDN for deployment verification.
output "sql_server_fqdn" {
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
  description = "The fully qualified domain name of the Azure SQL Server."
}