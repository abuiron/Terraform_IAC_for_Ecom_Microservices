variable "name" {
  description = "Name prefix for every resource, e.g. looksmatter-production."
  type        = string
}

variable "region" {
  description = "AWS region, used to build VPC endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "A /16 block for the VPC, e.g. 10.20.0.0/16. Use a different one per environment so they can be peered later."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 block, e.g. 10.20.0.0/16 (the subnet layout below assumes /16)."
  }
}

variable "az_count" {
  description = "How many Availability Zones to spread across. 3 survives the loss of a whole zone with capacity to spare."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (EKS needs at least 2, and the CIDR layout reserves room for 3)."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all zones (cheaper, fine for staging). false = one per zone (production: a zone outage can't cut internet access for the others)."
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Create private interface endpoints for AWS APIs (ECR, STS, CloudWatch Logs). Costs per endpoint per zone; worth it at high traffic or for compliance."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "AWS services that get an interface endpoint when enable_interface_endpoints is true."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "logs"]
}

variable "enable_flow_logs" {
  description = "Record network flows to CloudWatch Logs for security investigations."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "ALL, ACCEPT or REJECT. REJECT is cheapest and still shows blocked traffic; ALL is best for forensics."
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ALL, ACCEPT or REJECT."
  }
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps flow logs."
  type        = number
  default     = 30
}
