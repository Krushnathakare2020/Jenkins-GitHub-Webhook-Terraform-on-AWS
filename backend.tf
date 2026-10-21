terraform {
  backend "s3" {
    bucket       = "mrunal-devops-0926b1668"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
