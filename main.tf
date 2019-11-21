terraform {
  backend "remote" {
    hostname = "${var.tfe_hostname}"

    #organization = "hashicorp-v2"
    organization = "${var.tfe_organization}"

    workspaces {
      name = "tfe-policies-example"
    }
  }
}

provider "tfe" {
  hostname = "${var.tfe_hostname}"
  token    = "${var.tfe_token}"
  version  = "~> 0.6"
}

data "tfe_workspace_ids" "all" {
  names        = ["*"]
  organization = "${var.tfe_organization}"
}

locals {
  workspaces = "${data.tfe_workspace_ids.all.external_ids}" # map of names to IDs
}

resource "tfe_policy_set" "global" {
  name         = "global"
  description  = "Policies that should be enforced on ALL infrastructure."
  organization = "${var.tfe_organization}"
  global       = true

  # !! Bug causes AWS cidr block rule to fail during destroys.  Test once fixed
  #policy_ids = [
  #  "${tfe_sentinel_policy.aws-restrict-ingress-sg-rule-cidr-blocks.id}",
  #  "${tfe_sentinel_policy.azurerm-block-allow-all-cidr.id}",
  #  "${tfe_sentinel_policy.gcp-block-allow-all-cidr.id}",
  #]
  policy_ids = [
    "${tfe_sentinel_policy.azurerm-block-allow-all-cidr.id}",
    "${tfe_sentinel_policy.gcp-block-allow-all-cidr.id}",
    "${tfe_sentinel_policy.aws-restrict-ingress-sg-rule-cidr-blocks.id}",
  ]
}

resource "tfe_policy_set" "development" {
  name         = "development"
  description  = "Policies that should be enforced on development infrastructure."
  organization = "${var.tfe_organization}"

  policy_ids = [
    "${tfe_sentinel_policy.aws-restrict-instance-type-dev.id}",
    "${tfe_sentinel_policy.azurerm-restrict-vm-size.id}",
    "${tfe_sentinel_policy.gcp-restrict-machine-type.id}",
    "${tfe_sentinel_policy.limit-cost-by-workspace-type.id}",
  ]

  workspace_external_ids = [
    "${local.workspaces["patspets_dev"]}",
    "${local.workspaces["patspets_master"]}",
    "${local.workspaces["patspets_stage"]}",
  ]
}

# Test/experimental policies:

resource "tfe_sentinel_policy" "passthrough" {
  name         = "passthrough"
  description  = "Just passing through! Always returns 'true'."
  organization = "${var.tfe_organization}"
  policy       = "${file("./passthrough.sentinel")}"
  enforce_mode = "advisory"
}

# Sentinel management policies:

resource "tfe_sentinel_policy" "tfe_policies_only" {
  name         = "tfe_policies_only"
  description  = "The Terraform config that manages Sentinel policies must not use the authenticated tfe provider to manage non-Sentinel resources."
  organization = "${var.tfe_organization}"
  policy       = "${file("./tfe_policies_only.sentinel")}"
  enforce_mode = "hard-mandatory"
}

# Networking policies: Development
resource "tfe_sentinel_policy" "aws-restrict-ingress-sg-rule-cidr-blocks" {
  name         = "Sec-aws-ingress-cidr-0.0.0.0"
  description  = "Avoid nasty firewall mistakes (AWS version)"
  organization = "${var.tfe_organization}"
  policy       = "${file("./restrict-ingress-sg-rule-cidr-blocks.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "azurerm-block-allow-all-cidr" {
  name         = "Sec-azure-ingress-cidr-0.0.0.0"
  description  = "Avoid nasty firewall mistakes (Azure version)"
  organization = "${var.tfe_organization}"
  policy       = "${file("./azurerm-block-allow-all-cidr.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "gcp-block-allow-all-cidr" {
  name         = "Sec-gcp-ingress-cidr-0.0.0.0"
  description  = "Avoid nasty firewall mistakes (GCP version)"
  organization = "${var.tfe_organization}"
  policy       = "${file("./gcp-block-allow-all-cidr.sentinel")}"
  enforce_mode = "soft-mandatory"
}

# Compute instance policies:

resource "tfe_sentinel_policy" "aws-restrict-instance-type-dev" {
  name         = "aws-restrict-instance-type-dev"
  description  = "Limit AWS instances to approved list (for dev infrastructure)"
  organization = "${var.tfe_organization}"
  policy       = "${file("./restrict-ec2-instance-type.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "aws-restrict-instance-type-prod" {
  name         = "Std-aws-restrict-inst-type-prod"
  description  = "Limit AWS instances to approved list (for prod infrastructure)"
  organization = "${var.tfe_organization}"
  policy       = "${file("./aws-restrict-instance-type-prod.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "aws-restrict-instance-type-default" {
  name         = "Std-aws-restrict-inst-type"
  description  = "Limit AWS instances to approved list"
  organization = "${var.tfe_organization}"
  policy       = "${file("./aws-restrict-instance-type-default.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "azurerm-restrict-vm-size" {
  name         = "Std-azure-restrict-inst-type"
  description  = "Limit Azure instances to approved list"
  organization = "${var.tfe_organization}"
  policy       = "${file("./azurerm-restrict-vm-size.sentinel")}"
  enforce_mode = "soft-mandatory"
}

resource "tfe_sentinel_policy" "gcp-restrict-machine-type" {
  name         = "Std-gcp-restrict-inst-type"
  description  = "Limit GCP instances to approved list"
  organization = "${var.tfe_organization}"
  policy       = "${file("./gcp-restrict-machine-type.sentinel")}"
  enforce_mode = "soft-mandatory"
}

# Policy that requires modules to come from Private Module Registry
data "template_file" "require-modules-from-pmr" {
  template = "${file("./require-modules-from-pmr.sentinel")}"

  vars {
    hostname     = "${var.tfe_hostname}"
    organization = "${var.tfe_organization}"
  }
}

resource "tfe_sentinel_policy" "require-modules-from-pmr" {
  name         = "require-modules-from-pmr"
  description  = "Require all modules to come from the Private Module Registy of the current org"
  organization = "${var.tfe_organization}"
  policy       = "${data.template_file.require-modules-from-pmr.rendered}"
  enforce_mode = "hard-mandatory"
}

resource "tfe_sentinel_policy" "limit-cost-by-workspace-type" {
  name         = "Cost-aws-limit-cost-by-workspace"
  description  = "Limit cost by workspace type"
  organization = "${var.tfe_organization}"
  policy       = "${file("./limit-cost-by-workspace-type.sentinel")}"
  enforce_mode = "soft-mandatory"
}

