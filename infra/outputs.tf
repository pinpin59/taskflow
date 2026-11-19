output "url" {
  value       = "http://localhost:${var.front_port}/health"
  description = "URL de vérification du staging (health check)"
}
