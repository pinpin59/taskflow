terraform {
  required_version = ">= 1.6.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }
}

# Lit DOCKER_HOST s'il est défini, sinon /var/run/docker.sock
provider "docker" {}

# ── Réseau ────────────────────────────────────────────────────────────────────

resource "docker_network" "staging" {
  name = "taskflow-staging"
}

# ── Volume ────────────────────────────────────────────────────────────────────

resource "docker_volume" "pgdata" {
  name = "taskflow-staging-pgdata"
}

# ── Images ────────────────────────────────────────────────────────────────────

resource "docker_image" "postgres" {
  name         = "docker.io/library/postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  keep_locally = true
}

resource "docker_image" "front" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  keep_locally = true
}

# ── Conteneurs ────────────────────────────────────────────────────────────────

resource "docker_container" "db" {
  name    = "taskflow-staging-db"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=taskflow",
  ]

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.staging.name
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 10
    start_period = "0s"
  }
}

resource "docker_container" "api" {
  name    = "taskflow-staging-api"
  image   = docker_image.api.image_id
  restart = "unless-stopped"

  # DATABASE_URL utilise le nom du conteneur db comme hôte DNS sur le réseau Docker
  env = [
    "APP_ENV=staging",
    "DATABASE_URL=postgres://taskflow:${var.postgres_password}@taskflow-staging-db:5432/taskflow",
  ]

  networks_advanced {
    name    = docker_network.staging.name
    aliases = ["api"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "10s"
  }

  depends_on = [docker_container.db]
}

resource "docker_container" "front" {
  name    = "taskflow-staging-front"
  image   = docker_image.front.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.front_port
  }

  networks_advanced {
    name = docker_network.staging.name
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "5s"
  }

  depends_on = [docker_container.api]
}
