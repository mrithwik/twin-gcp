variable "project_id" {
  description = "GCP project ID (dedicated project for this app)"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run, Artifact Registry, Firestore"
  type        = string
  default     = "us-central1"
}

variable "gemini_api_key" {
  description = "Google Gemini API key, stored in Secret Manager"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy service account, as \"owner/repo\""
  type        = string
}

variable "vercel_api_token" {
  description = "Vercel API token (personal token with access to create/manage the project)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vercel_team_id" {
  description = "Vercel team ID, if the project should live under a team instead of a personal account"
  type        = string
  default     = null
}

variable "gemini_model_id" {
  description = "Gemini model ID. \"gemini-flash-latest\" is Google's alias for the current recommended flash-tier model, which avoids breakage when specific dated model IDs get deprecated for new API keys/projects."
  type        = string
  default     = "gemini-flash-latest"
}

variable "cors_origin" {
  description = "Frontend origin allowed by the backend's CORS policy"
  type        = string
  default     = "http://localhost:3000"
}
