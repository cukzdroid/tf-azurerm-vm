provider "azurerm" {
  version = ">=1.29.0"
  features {}
}

data "azurerm_resource_group" "cukzvm01" {
  name      = "cukzrg"
}

data "azurerm_virtual_network" "cukzvm01" {
  name                = "cukzvmnet"
  resource_group_name = data.azurerm_resource_group.cukzvm01.name
}

data "azurerm_subnet" "cukzvm01" {
    name                 = "cukzsnet01"
    virtual_network_name = data.azurerm_virtual_network.cukzvm01.name
    resource_group_name  = data.azurerm_resource_group.cukzvm01.name
}

# Create public IPs
resource "azurerm_public_ip" "cukzvm01" {
    name                         = "cukzvm01-ippublic"
    location                     = data.azurerm_resource_group.cukzvm01.location
    resource_group_name          = data.azurerm_resource_group.cukzvm01.name
    allocation_method            = "Dynamic"

    tags = {
        environment = "cukz dev"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "cukzvm01" {

    name                            = "cukzvm01-nsg"
    location                        = data.azurerm_resource_group.cukzvm01.location
    resource_group_name             = data.azurerm_resource_group.cukzvm01.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "cukz dev"
    }
}


# Create network interface
resource "azurerm_network_interface" "cukzvm01" {
    name                              = "cukzvm01-nic"
    location                          = data.azurerm_resource_group.cukzvm01.location
    resource_group_name               = data.azurerm_resource_group.cukzvm01.name

    ip_configuration {
        name                          = "cukzvm01-nic-config"
        subnet_id                     = data.azurerm_subnet.cukzvm01.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.cukzvm01.id
    }

    tags = {
        environment = "cukz dev"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "cukzvm01" {
    network_interface_id            = azurerm_network_interface.cukzvm01.id
    network_security_group_id       = azurerm_network_security_group.cukzvm01.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group_name = data.azurerm_resource_group.cukzvm01.name
    }

    byte_length = 8
}


# Create storage account for boot diagnostics
resource "azurerm_storage_account" "cukzvm01" {
    name                            = "diag${random_id.randomId.hex}"
    resource_group_name             = data.azurerm_resource_group.cukzvm01.name
    location                        = data.azurerm_resource_group.cukzvm01.location
    account_tier                    = "Standard"
    account_replication_type        = "LRS"

    tags = {
        environment = "cukz dev"
    }
}

# Create (and display) an SSH key
resource "tls_private_key" "cukzvm01" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { value = tls_private_key.cukzvm01.private_key_pem }

# Create virtual machine
resource "azurerm_linux_virtual_machine" "cukzvm01" {
    name                          = "cukzvm01"
    location                      = data.azurerm_resource_group.cukzvm01.location
    resource_group_name           = data.azurerm_resource_group.cukzvm01.name
    network_interface_ids         = [azurerm_network_interface.cukzvm01.id]
    size                          = "Standard_B1s"

    os_disk {
        name                      = "cukzvm01_OsDisk"
        caching                   = "ReadWrite"
        storage_account_type      = "Standard_LRS"
    }

    source_image_reference {
        publisher = "OpenLogic"
        offer     = "CentOS"
        sku       = "7.5"
        version   = "latest"
    }

    computer_name  = "cukzvm01"
    admin_username = "sysadm"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "sysadm"
        public_key     = tls_private_key.cukzvm01.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.cukzvm01.primary_blob_endpoint
    }

    tags = {
        environment = "cukz dev"
    }
}
