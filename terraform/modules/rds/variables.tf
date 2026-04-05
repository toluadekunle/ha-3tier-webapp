variable "project_name"       { type = string }
variable "environment"        { type = string }
variable "subnet_ids"         { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "db_name"            { type = string }
variable "db_username"        { type = string }
variable "db_password"        { type = string; sensitive = true }
variable "instance_class"     { type = string }
variable "engine_version"     { type = string }
variable "multi_az"           { type = bool;   default = true }
