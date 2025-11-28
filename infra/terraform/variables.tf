variable "project" {
  description = "Nombre del proyecto para tags y prefijos"
  type        = string
  default     = "provesi"
}

variable "region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC donde crear recursos"
  type        = string
}

variable "subnet_id" {
  description = "Subred pública para la instancia"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDRs permitidos para acceso"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_app_ports" {
  description = "Puertos de app a exponer"
  type        = list(number)
  default     = [8000, 8001, 8080, 8089, 8090, 8443]
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t2.micro"
}

variable "key_pair_name" {
  description = "Nombre del key pair a usar/crear"
  type        = string
}

variable "create_key_pair" {
  description = "Crear el key pair desde la clave pública proporcionada"
  type        = bool
  default     = false
}

variable "public_key" {
  description = "Clave pública SSH si se crea el key pair"
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "URL del repositorio git a clonar"
  type        = string
  default     = ""
}

variable "checkout_branch" {
  description = "Rama a chequear"
  type        = string
  default     = "main"
}

variable "orders_port" {
  description = "Puerto ms-orders"
  type        = number
  default     = 8001
}

variable "order_detail_port" {
  description = "Puerto ms-order-detail"
  type        = number
  default     = 8080
}

variable "guard_port" {
  description = "Puerto ms-security-guard"
  type        = number
  default     = 8090
}
