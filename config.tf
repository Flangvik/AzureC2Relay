#Azure location for deployment
variable "location"    { default = "westeurope"}

//Public SSH key to be placed on the teamserver VM
variable "ssh_key"    { default = "<PUBLIC SSH KEY>"}

//Your profile name , must be placed in Ressources/ (Just the name here, not path!)
variable "PROFILE_FILE"    { default = "jquery-c2.4.2.profile" }

#Use a long password instead of special chars, migh break bash command
variable "TEAM_PASS"    { default = "<TEAM SERVER PASSWORD>" }

#Serial key for installing cobalt teamserver
variable "COBALTKEY"    { default = "<COBALT SERIAL KEY>" }

#Azure function name without <.azurewebsites.net>
variable "func_name"    { default = "<AZURE FUNC NAME>" }

#CDN Endpoint name without <.azureedge.net>
variable "cdn_endpoint_name"    { default = "<CDN ENDPOINT NAME>" }

#Site to redirect traffic to that dosent not match mall profile
variable "decoy_website"    { default = "https://microsoft.com" }

#MUST BE REPLACED TO AVOID COLISSION WITH OTHER AZURE GLOBAL RESSOURCES 
variable "uniq_prefix"    { default = "<RANDOM 4 LETTERS>" }

#No need to edit anything below this line!
variable "cdn_profile_name"    { default = "relay-cdn-profile"}
variable "resource_group"    { default = "relay-rg"}
variable "vm_name"    { default = "relay-teamserver-vm"}
variable "plan_name"    { default = "relay-appsvc"}
variable "stor_name"    { default = "relaydata001"}
variable "vm_username"    { default = "azureuser" }
variable "vm_diskname"    { default = "relayteamservervmsto0" }
variable "nic_name"    { default = "relay-1nic" }
variable "public_ip_name"    { default = "relay-pia" }
variable "nic_sec_name"    { default = "relay-nsg" }
variable "subnet_one_name"    { default = "vm-subnet" }
variable "subnet_two_name"    { default = "func-subnet" }
variable "vnet_name"    { default = "relay-vnet" }

variable "func_zip_path"    { default = "AzureC2Relay.zip" }

