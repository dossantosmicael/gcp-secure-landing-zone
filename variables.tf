variable "gcp_project_id" {
  type        = string
  description = "projeto-landing-zone-478512"
}

variable "gcp_region" {
  type        = string
  description = "A região onde os recursos serão criados."
  default     = "southamerica-east1"
}

variable "gcp_zone" {
  type        = string
  description = "A zona dentro da região."
  default     = "southamerica-east1-a"
}