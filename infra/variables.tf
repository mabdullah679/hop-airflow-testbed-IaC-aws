variable "name_prefix" {
  type    = string
  default = "pf-hop-airflow"
}

variable "allowed_cidr" {
  type        = string
  description = "Only this CIDR may reach the Airflow UI (port 8080). Use your /32."
  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) && var.allowed_cidr != "0.0.0.0/0"
    error_message = "allowed_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}
