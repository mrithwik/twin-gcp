output "cloud_run_url" {
  description = "Backend URL (set as the frontend's NEXT_PUBLIC_API_URL)"
  value       = google_cloud_run_v2_service.backend.uri
}

output "artifact_registry_repo" {
  description = "Docker repo path used by the CI/CD workflow to push images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "github_deployer_service_account" {
  description = "Service account email GitHub Actions impersonates via Workload Identity Federation"
  value       = google_service_account.github_deployer.email
}

output "workload_identity_provider" {
  description = "Full WIF provider resource name — set as the GitHub Actions secret GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}
