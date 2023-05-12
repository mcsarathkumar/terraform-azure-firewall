locals {
    location = "eastus"
    hub_rg = "hub-rg"
    spoke_rg = "spoke-rg"
}

resource "azurerm_resource_group" "hub_rg" {
  name = local.hub_rg
  location = local.location
}

resource "azurerm_resource_group" "spoke_rg" {
  name = local.spoke_rg
  location = local.location
}

resource "azurerm_virtual_network" "hub_vnet" {
  name = "hub-vnet"
  address_space = ["10.0.0.0/16"]
  location = local.location
  resource_group_name = azurerm_resource_group.hub_rg.name
}

resource "azurerm_subnet" "hub_vnet_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_virtual_network" "spoke_vnet" {
  name = "spoke-vnet"
  address_space = ["10.1.0.0/16"]
  location = local.location
  resource_group_name = azurerm_resource_group.spoke_rg.name
}

resource "azurerm_subnet" "spoke_vnet_subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.spoke_rg.name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = ["10.1.0.0/24"]
}


resource "azurerm_virtual_network_peering" "hub_spoke_peer" {
    name = "hub-spoke-peer"
    resource_group_name = azurerm_resource_group.hub_rg.name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.spoke_vnet.id
}

resource "azurerm_virtual_network_peering" "spoke_hub_peer" {
    name = "spoke-hub-peer"
    resource_group_name = azurerm_resource_group.spoke_rg.name
    virtual_network_name = azurerm_virtual_network.spoke_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
}

resource "azurerm_public_ip" "windows_pip" {
    name = "windows-pip"
    location = local.location
    resource_group_name = azurerm_resource_group.spoke_rg.name
    allocation_method = "Dynamic"
}

resource "azurerm_network_interface" "windows_nic" {
    name = "windows-nic"
    location = local.location
    resource_group_name = azurerm_resource_group.spoke_rg.name

    ip_configuration {
        name                          = "internal"
        subnet_id = azurerm_subnet.spoke_vnet_subnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_network_security_group" "spoke_nsg" {
  name = "spoke-nsg"
    location = local.location
    resource_group_name = azurerm_resource_group.spoke_rg.name

    security_rule {
        name                       = "RDP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_windows_virtual_machine" "windows_vm" {
  name                = "windows-vm"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = local.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  admin_password      = "P@ssword12345"
  network_interface_ids = [
    azurerm_network_interface.windows_nic.id
  ]

  os_disk {
    name = "windows-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "firewall_pip" {
    name = "firewall-pip"
    location = local.location
    resource_group_name = azurerm_resource_group.hub_rg.name
    allocation_method = "Static"
    sku = "Standard"
}

resource "azurerm_firewall_policy" "firewall_policy" {
  name = "firewall-policy"
  location = local.location
    resource_group_name = azurerm_resource_group.hub_rg.name
}

resource "azurerm_firewall" "firewall" {
  name                = "firewall"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.hub_vnet_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }
}

resource "azurerm_log_analytics_workspace" "hub_log" {
  name               = "hub-log"
    location           = local.location
    resource_group_name = azurerm_resource_group.hub_rg.name
    sku = "PerGB2018"
      retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "firewall_hub_log" {
    name = "firewall-hub-log"
    target_resource_id = azurerm_firewall.firewall.id
    log_analytics_workspace_id = azurerm_log_analytics_workspace.hub_log.id
    enabled_log {
        category = "AllLogs"
        retention_policy {
            enabled = false
        }
    }
    metric {
        category = "AllMetrics"
        retention_policy {
          enabled = true
        }
    } 
}