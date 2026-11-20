variable "name" {
  description = "Name prefix, e.g. looksmatter-production."
  type        = string
}

variable "domain_names" {
  description = "Storefront domains. The first one is the certificate's main name, e.g. [\"looksmatter.in\", \"www.looksmatter.in\"]."
  type        = list(string)

  validation {
    condition     = length(var.domain_names) > 0
    error_message = "Give at least one storefront domain."
  }
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone that holds the storefront domains."
  type        = string
}

variable "force_destroy" {
  description = "Let `terraform destroy` delete the bucket even though it holds files and old versions. Apply the change before destroying: Terraform reads it from state."
  type        = bool
  default     = false
}

variable "price_class" {
  description = "CloudFront edge locations to use. PriceClass_200 includes India; PriceClass_100 does not (North America, Europe and Israel only)."
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}
