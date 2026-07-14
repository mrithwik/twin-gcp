terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 1.0"
    }
  }

  # Local state on purpose: this is a single-maintainer personal project, so a
  # remote GCS backend + locking (as used in the AWS/twin repo's multi-env
  # setup) would be more infrastructure than the project needs. terraform.tfstate
  # is git-ignored.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "vercel" {
  # Falls back to a dummy value when unset so the provider can initialize even
  # when the Vercel side is being managed via the CLI instead of Terraform
  # (see vercel_project's count in main.tf). Never used for actual API calls
  # unless vercel_api_token is real and vercel_project is created.
  api_token = var.vercel_api_token != "" ? var.vercel_api_token : "0000000000000000000000ab"
}
