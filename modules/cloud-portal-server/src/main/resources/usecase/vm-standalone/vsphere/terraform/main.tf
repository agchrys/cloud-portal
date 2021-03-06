provider "null" {
  version = "1.0.0"
}

provider "vsphere" {
  vsphere_server = "${var.vcenter_hostname}"
  user = "${var.vcenter_username}"
  password = "${var.vcenter_password}"
  allow_unverified_ssl = "true"
  version = "1.2.0"
}

locals {
  is_linux = "${replace(var.image_name, "Linux", "") != var.image_name ? 1 : 0}"
  linux_temp_folder_path = "/tmp"
  linux_script_folder_name = "linux_scripts"
  linux_script_folder_path = "${local.linux_temp_folder_path}/${local.linux_script_folder_name}"
  linux_prepare_script_path = "${local.linux_script_folder_path}/prepare.sh"
  linux_user_script_path = "${local.linux_script_folder_path}/user.sh"
  linux_cleanup_script_path = "${local.linux_script_folder_path}/cleanup.sh"
  
  is_windows = "${replace(var.image_name, "Windows", "") != var.image_name ? 1 : 0}"
  windows_temp_folder_path = "C:\\"
  windows_script_folder_name = "windows_scripts"      
  windows_script_folder_path = "${local.windows_temp_folder_path}\\${local.windows_script_folder_name}"
  windows_prepare_script_path = "${local.windows_script_folder_path}\\prepare.ps1"
  windows_user_script_path = "${local.windows_script_folder_path}\\user.ps1"
  windows_cleanup_script_path = "${local.windows_script_folder_path}\\cleanup.ps1"
}

data "vsphere_datacenter" "dc" {
  name = "${var.vcenter_datacenter}"
}

data "vsphere_datastore" "datastore" {
  name          = "${var.vcenter_datastore}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.vcenter_resource_pool}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "${var.vcenter_network}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${lookup(local.image_templates_map, var.image_name)}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_custom_attribute" "title" {
  name = "Title"
}

data "vsphere_custom_attribute" "description" {
  name = "Description"
}

data "vsphere_custom_attribute" "creation_date" {
  name = "CreationDate"
}

data "vsphere_custom_attribute" "owned_by" {
  name = "OwnedBy"
}

data "vsphere_custom_attribute" "owner_group" {
  name = "OwnerGroup"
}

data "vsphere_custom_attribute" "provisioning_system" {
  name = "ProvisioningSystem"
}

resource "vsphere_virtual_machine" "linux" {

  count = "${local.is_linux}"
  name = "${var.random_id}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"
  num_cpus = "${var.vm_cores}"
  memory = "${var.vm_ram_size}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"
  folder = "${var.vcenter_target_folder}"

  network_interface {
    network_id = "${data.vsphere_network.network.id}"
  }

  disk {
    name = "${var.random_id}.vmdk"
    size = "${var.vm_disk_size}"
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"    
  }  
  
  connection {
    type = "ssh"
    agent = false  
    host = "${vsphere_virtual_machine.linux.guest_ip_addresses.0}"
    user = "${local.linux_default_username}" 
    password = "${local.linux_default_password}"     
    timeout = "1m"      
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo '${local.linux_default_password}' | sudo -S echo test",
      "sudo apt-get update",
      "sudo apt-get install -y whois",
      "sudo useradd -p \"$(mkpasswd --hash=md5 ${var.password})\" -s '/bin/bash' '${var.username}'",
      "sudo usermod -aG sudo '${var.username}'",
      "sudo mkdir -p '/home/${var.username}/.ssh'",
      "sudo bash -c \"echo '${file(var.public_key_file)}' >> '/home/${var.username}/.ssh/authorized_keys'\"",
      "sudo chown -R '${var.username}.${var.username}' '/home/${var.username}'"
    ]
  }  
  
  custom_attributes = "${map(
    data.vsphere_custom_attribute.title.id, "${var.title}",
    data.vsphere_custom_attribute.description.id, "${var.description}",
    data.vsphere_custom_attribute.creation_date.id, "${var.creation_date}",
    data.vsphere_custom_attribute.owned_by.id, "${var.owner}",
    data.vsphere_custom_attribute.owner_group.id, "${var.group}",
    data.vsphere_custom_attribute.provisioning_system.id, "${var.application_url}"
  )}"
}

resource "null_resource" "linuxprovisioning" {
  
  count = "${local.is_linux}"
  
  connection {
    type = "ssh"
    agent = false  
    host = "${vsphere_virtual_machine.linux.guest_ip_addresses.0}"
    user = "${var.username}" 
    password = "${var.password}"     
    timeout = "1m"      
  }

  provisioner "file" {
    source      = "${local.linux_script_folder_name}"
    destination = "${local.linux_temp_folder_path}"  
  } 

  provisioner "file" {
    source      = "${var.script_file}"
    destination = "${local.linux_user_script_path}"  
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo '${var.password}' | sudo -S echo test",
      "bash '${local.linux_prepare_script_path}' '${var.random_id}'",
      "bash '${local.linux_user_script_path}'",
      "bash '${local.linux_cleanup_script_path}'",
      "rm -rf ${local.linux_script_folder_path}"
    ]
  } 
  
  depends_on = ["vsphere_virtual_machine.linux"]
}

resource "vsphere_virtual_machine" "windows" {

  count = "${local.is_windows}"
  name = "${var.random_id}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"

  num_cpus = "${var.vm_cores}"
  memory = "${var.vm_ram_size}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"
  folder = "${var.vcenter_target_folder}"

  network_interface {
    network_id = "${data.vsphere_network.network.id}"
  }

  disk {
    name = "${var.random_id}.vmdk"
    size = "${var.vm_disk_size}"
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"    
  }  
  
  connection {
    type = "winrm"
    host = "${vsphere_virtual_machine.windows.guest_ip_addresses.0}"
    user = "${local.windows_default_username}" 
    password = "${local.windows_default_password}"          
    timeout = "10m"      
  }

  provisioner "remote-exec" {
    inline = [
      "NET USER ${var.username} ${var.password} /add /y /expires:never",
      "NET LOCALGROUP Administrators ${var.username} /add",
      "WMIC USERACCOUNT WHERE \"Name='${var.username}'\" SET PasswordExpires=FALSE"
    ]
  }
  
  custom_attributes = "${map(
    data.vsphere_custom_attribute.title.id, "${var.title}",
    data.vsphere_custom_attribute.description.id, "${var.description}",
    data.vsphere_custom_attribute.creation_date.id, "${var.creation_date}",
    data.vsphere_custom_attribute.owned_by.id, "${var.owner}",
    data.vsphere_custom_attribute.owner_group.id, "${var.group}",
    data.vsphere_custom_attribute.provisioning_system.id, "${var.application_url}"
  )}"
}

resource "null_resource" "windowsprovisioning" {
  
  count = "${local.is_windows}"
  
  connection {
    type = "winrm"
    host = "${vsphere_virtual_machine.windows.guest_ip_addresses.0}"
    user = "${var.username}" 
    password = "${var.password}"          
    timeout = "10m"      
  }

  provisioner "file" {
    source      = "${local.windows_script_folder_name}"
    destination = "${local.windows_script_folder_path}"  
  }

  provisioner "file" {
    source = "${var.script_file}"
    destination = "${local.windows_user_script_path}" 
  } 
  
  provisioner "remote-exec" {
    inline = [
      "Powershell.exe -ExecutionPolicy Unrestricted -File ${local.windows_prepare_script_path} ${var.random_id}",      
      "Powershell.exe -ExecutionPolicy Unrestricted -File ${local.windows_user_script_path}",
      "Powershell.exe -ExecutionPolicy Unrestricted -File ${local.windows_cleanup_script_path}",
      "Powershell.exe -ExecutionPolicy Unrestricted -Command Remove-Item ${local.windows_script_folder_path} -Force -Recurse"      
    ]
  } 
  
  depends_on = ["vsphere_virtual_machine.windows"]
}