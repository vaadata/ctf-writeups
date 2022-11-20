# https://registry.terraform.io/providers/digitalocean/digitalocean/latest

terraform {
  cloud {
    organization = "vaadata"
    workspaces {
      name = "blog"
    }
  }
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
variable "do_token" {}

variable "gh_token" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_app" "blog" {
  # https://docs.digitalocean.com/products/app-platform/references/app-specification-reference/
  spec {
    name   = "blog"
    region = "fra"

    domain {
      name = "blog.vaadata.it"
      type = "PRIMARY"
      wildcard = false
      zone = "vaadata.it"
    }

    static_site {
      name          = "blog"
      build_command = "pip install git+https://${GH_TOKEN}@github.com/squidfunk/mkdocs-material-insiders.git p && mkdocs build"
      output_dir    = "site"
      github {
        repo = "vaadata/blog"
        branch = "main"
        deploy_on_push = true
      }

      env {
        key = "GH_TOKEN"
        value = var.gh_token
      }
    }
  }
}