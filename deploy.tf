# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}


provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.uniq_prefix}${var.resource_group}"
  location = "${var.location}"
}


resource "azurerm_resource_group_template_deployment" "azure_cdn" {
    name                = "azurecdn"
    resource_group_name = azurerm_resource_group.rg.name
    deployment_mode     = "Incremental"
    template_content    = file("arm_template.json")
 
    parameters_content =  jsonencode({
        cdn_profile_name              = {value =  "${var.uniq_prefix}${var.cdn_profile_name}"}
        endpoint_name                 = {value =  "${var.cdn_endpoint_name}"}
        app_func_name                 = {value =  "${var.func_name}.azurewebsites.net"}
        location                      = {value =  "${var.location}"}
    })  
}


resource "azurerm_storage_account" "storage" {
  name                     = "${var.uniq_prefix}${var.stor_name}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_app_service_plan" "servplan" {
  name                =  "${var.uniq_prefix}${var.plan_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Standard"
    size = "P1V2"
  }
}

resource "azurerm_function_app" "func" {
  name                       = "${var.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.servplan.id
  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  os_type                    = "linux"
  version	                 = "~2"
  app_settings = {
    FUNCTIONS_EXTENSION_VERSION                 = "~2"
    FUNCTIONS_WORKER_RUNTIME                    = "dotnet"
    SCM_DO_BUILD_DURING_DEPLOYMENT              = true
    MalleableProfileB64                          = "${data.local_file.ParseMalleable.content}"
    RealC2EndPoint								= "https://${azurerm_linux_virtual_machine.vm.private_ip_address}:443/"
  	DecoyRedirect								= "${var.decoy_website}"
	APPINSIGHTS_INSTRUMENTATIONKEY				= "${azurerm_application_insights.funcai.instrumentation_key}"
    
    }

	site_config {
		always_on   = "true"
	}

   depends_on = [
    azurerm_linux_virtual_machine.vm,
    data.local_file.ParseMalleable,
	azurerm_application_insights.funcai
  ]
  

}

resource "azurerm_application_insights" "funcai" {
  name                = "${var.uniq_prefix}${var.ai_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}



resource "azurerm_virtual_network" "vnet" {
  name                = "${var.uniq_prefix}${var.vnet_name}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

}

resource "azurerm_subnet" "subnet1" {
  name                 = "${var.uniq_prefix}${var.subnet_one_name}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
 depends_on = [
   azurerm_virtual_network.vnet,
   ]


}


resource "azurerm_subnet" "subnet2" {
  name                 = "${var.uniq_prefix}${var.subnet_two_name}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

    delegation {
      name = "subnetdelegation"

      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }

 depends_on = [
   azurerm_virtual_network.vnet,
   ]

}

resource "azurerm_public_ip" "pubip" {
  name                = "${var.uniq_prefix}${var.public_ip_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"

  }
  
  resource "azurerm_network_security_group" "nicsec" {
  name                = "${var.uniq_prefix}${var.nic_sec_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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

}

resource "azurerm_network_interface" "nic" {
  name                = "${var.uniq_prefix}${var.nic_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pubip.id
  }
 depends_on = [
   azurerm_subnet.subnet1,
   ]

}


resource "azurerm_network_interface_security_group_association" "nicass" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nicsec.id

 depends_on = [
        azurerm_network_interface.nic,
  ]

}


resource "tls_private_key" "public_private_key_pair" {
  algorithm   = "RSA"
}


# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
    name                  = "${var.uniq_prefix}${var.vm_name}"
    location              = azurerm_resource_group.rg.location
    resource_group_name   = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.nic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "${var.uniq_prefix}${var.vm_diskname}"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "teamservervm"
    admin_username = "${var.vm_username}"
    disable_password_authentication = true

    admin_ssh_key {
	    username   = "${var.vm_username}"
	    public_key = tls_private_key.public_private_key_pair.public_key_openssh
    }
	
	provisioner "file" {
	  source      = "Ressources/"
	  destination = "/home/${var.vm_username}/"

	  connection {
		type        = "ssh"
		user        = "${var.vm_username}"
		private_key =  tls_private_key.public_private_key_pair.private_key_pem
		timeout     = "2m"
		host        = "${self.public_ip_address}"
	  }
	}

  provisioner "remote-exec" {
 
	  inline = [
      "echo \"${var.ssh_key}\" >> ~/.ssh/authorized_keys",
      "sudo apt update -y",
      "sudo apt -f install openjdk-11-jre-headless -y",
	  "sudo apt -f install openjdk-11-jdk-headless -y",
      "tar xvf cobaltstrike-dist.tgz",
      "rm cobaltstrike-dist.tgz",
      "cd cobaltstrike", 
      "echo \"${var.COBALTKEY}\" | bash update", 
      "cp ~/${var.PROFILE_FILE} ~/cobaltstrike/${var.PROFILE_FILE}",
      "echo \"sudo bash teamserver ${self.private_ip_address} ${var.TEAM_PASS} ${var.PROFILE_FILE}\" > RunServer.sh",
      "tmux new-session -d -s CobaltTeamServer 'sudo bash RunServer.sh'",
      ]

	  connection {
		type        = "ssh"
		user        = "${var.vm_username}"
		private_key =  tls_private_key.public_private_key_pair.private_key_pem
		timeout     = "10m"
		host        = "${self.public_ip_address}"
	  }
	}

	
   depends_on = [
	  azurerm_network_interface_security_group_association.nicass,
   
  ]

}


resource "time_sleep" "wait_60_seconds" {
  depends_on = [null_resource.funcrestart]

  create_duration = "60s"
}



resource "null_resource" "funcrestart" {

  provisioner "local-exec" {
    command = "az functionapp restart --name ${var.func_name} --resource-group ${azurerm_resource_group.rg.name}"
	}

 depends_on = [
    azurerm_app_service_virtual_network_swift_connection.funcass,
  ]

}

resource "null_resource" "funcdep" {
  provisioner "local-exec" {
    command = "az functionapp deployment source config-zip -g ${azurerm_resource_group.rg.name} -n ${var.func_name} --src ${var.func_zip_path} --build-remote true"
  }

 depends_on = [
    time_sleep.wait_60_seconds,
  ]

}

resource "azurerm_app_service_virtual_network_swift_connection" "funcass" {
  app_service_id = azurerm_function_app.func.id
  subnet_id      = azurerm_subnet.subnet2.id

   depends_on = [
	   azurerm_function_app.func,
	   azurerm_subnet.subnet2
   ]
}



resource "null_resource" "shell" {
  provisioner "local-exec" {
    command = "dotnet ParseMalleable/ParseMalleable.dll Ressources/${var.PROFILE_FILE} > ParsedMalleableData.txt"
  }
 
}

data "local_file" "ParseMalleable" {
		filename = "ParsedMalleableData.txt"	
		depends_on = [null_resource.shell,]
}



#Output SSH data for interaction with VM
output "ssh_vm" {
  value = "ssh -L 50050:localhost:50050 ${var.vm_username}@${azurerm_linux_virtual_machine.vm.public_ip_address}"

  depends_on = [
   null_resource.funcdep,
   ]

}

#Output CDN endpoint name
output "cdn_endpoint" {
  value = "${var.cdn_endpoint_name}.azureedge.net"

  depends_on = [
    azurerm_resource_group_template_deployment.azure_cdn,
   ]

}
