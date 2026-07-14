locals {
  services = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "firestore.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Artifact Registry -------------------------------------------------------

resource "google_artifact_registry_repository" "backend" {
  location      = var.region
  repository_id = "twin-backend"
  description   = "Digital twin backend container images"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# --- Firestore (conversation memory) ----------------------------------------

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.apis]
}

# --- Secret Manager (Gemini API key) ----------------------------------------

resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "gemini-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "gemini_api_key" {
  secret      = google_secret_manager_secret.gemini_api_key.id
  secret_data = var.gemini_api_key
}

# --- Cloud Run runtime service account ---------------------------------------

resource "google_service_account" "cloud_run_runtime" {
  account_id   = "twin-backend-runtime"
  display_name = "Digital Twin backend runtime (Cloud Run)"
}

resource "google_secret_manager_secret_iam_member" "runtime_secret_access" {
  secret_id = google_secret_manager_secret.gemini_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

resource "google_project_iam_member" "runtime_firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

# --- Cloud Run service ---------------------------------------------------------

resource "google_cloud_run_v2_service" "backend" {
  name                = "twin-backend"
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run_runtime.email

    containers {
      # Placeholder image on first apply; GitHub Actions deploys new
      # revisions with a real image afterwards (see lifecycle block below).
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "MEMORY_BACKEND"
        value = "firestore"
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "CORS_ORIGINS"
        value = var.cors_origin
      }
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  name     = google_cloud_run_v2_service.backend.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- GitHub Actions deploy identity (Workload Identity Federation) ----------

resource "google_service_account" "github_deployer" {
  account_id   = "twin-github-deployer"
  display_name = "GitHub Actions deployer for twin-backend"
}

resource "google_project_iam_member" "deployer_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "deployer_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "deployer_act_as_runtime" {
  service_account_id = google_service_account.cloud_run_runtime.name
  role                = "roles/iam.serviceAccountUser"
  member              = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id         = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                      = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = google_service_account.github_deployer.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# --- Vercel project (frontend) ----------------------------------------------

resource "vercel_project" "frontend" {
  count = var.vercel_api_token == "" ? 0 : 1

  name      = "twin-gcp"
  framework = "nextjs"
  root_directory = "frontend"
  team_id   = var.vercel_team_id

  environment = [
    {
      key    = "NEXT_PUBLIC_API_URL"
      value  = google_cloud_run_v2_service.backend.uri
      target = ["production", "preview"]
    }
  ]
}
