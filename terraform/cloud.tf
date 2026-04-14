terraform {
  cloud {
    organization = "Cybserve"

    workspaces {
      name = "ha-3tier-webapp-prod"
    }
  }
}
