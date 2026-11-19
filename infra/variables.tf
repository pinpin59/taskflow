variable "image_tag" {
  type        = string
  description = "Tag des images ghcr.io à déployer (ex : SHA court)"
  default     = "latest"
}

variable "ghcr_owner" {
  type        = string
  description = "Propriétaire GHCR, en minuscules (compte ou organisation GitHub)"
}

variable "front_port" {
  type        = number
  description = "Port d'exposition du front sur l'hôte"
  default     = 8081

  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "Le port doit être compris entre 1024 et 65535."
  }
}

variable "postgres_password" {
  type        = string
  description = "Mot de passe PostgreSQL (sensible)"
  sensitive   = true
}
