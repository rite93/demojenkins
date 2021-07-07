terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = "d1ed4df9-841a-4e20-a75f-8ec1e73c7f59"
  client_id = "c36fdb6a-6958-4784-a26b-2456bc86b9c2"
  client_secret="U.2KuPb8_2wwn3CqZAedFPgDzkulrgtuyu"
  tenant_id = "654d8ab0-dbda-487d-b27a-bad697ae17b4"
}


resource "azurerm_resource_group" "vm-scaleset" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "vm-scaleset" {
  name                = "virtual-networkdemo"
  address_space       = ["11.0.0.0/16"]
  location            = azurerm_resource_group.vm-scaleset.location
  resource_group_name = azurerm_resource_group.vm-scaleset.name
}

resource "azurerm_subnet" "vm-scaleset" {
  name                 = "subnetdemo"
  resource_group_name  = azurerm_resource_group.vm-scaleset.name
  virtual_network_name = azurerm_virtual_network.vm-scaleset.name
  address_prefixes     = ["11.0.1.0/24"]
}

resource "azurerm_public_ip" "vm-scaleset" {
  name                = "test"
  location            = azurerm_resource_group.vm-scaleset.location
  resource_group_name = azurerm_resource_group.vm-scaleset.name
  allocation_method   = "Static"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_lb" "vm-scaleset" {
  name                = "test"
  location            = azurerm_resource_group.vm-scaleset.location
  resource_group_name = azurerm_resource_group.vm-scaleset.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vm-scaleset.id
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = azurerm_resource_group.vm-scaleset.name
  loadbalancer_id     = azurerm_lb.vm-scaleset.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_nat_pool" "lbnatpool" {
  resource_group_name            = azurerm_resource_group.vm-scaleset.name
  name                           = "ssh"
  loadbalancer_id                = azurerm_lb.vm-scaleset.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_probe" "vm-scaleset" {
  resource_group_name = azurerm_resource_group.vm-scaleset.name
  loadbalancer_id     = azurerm_lb.vm-scaleset.id
  name                = "http-probe"
  protocol            = "Http"
  request_path        = "/health"
  port                = 8080
}

resource "tls_private_key" "vm-scaleset" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "azurerm_virtual_machine_scale_set" "vm-scaleset" {
  name                = "mytestscaleset-1"
  location            = azurerm_resource_group.vm-scaleset.location
  resource_group_name = azurerm_resource_group.vm-scaleset.name
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/myadmin/.ssh/authorized_keys"
      key_data = file("~/.ssh/demo_key.pub")
    }
  }

  # automatic rolling upgrade
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }

  # required when using rolling upgrade policy
  health_probe_id = azurerm_lb_probe.vm-scaleset.id

  sku {
    name     = "Standard_F2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "testvm"
    admin_username       = "myadmin"
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "TestIPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.vm-scaleset.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.lbnatpool.id]
    }
  }

  tags = {
    environment = "staging"
  }
}
