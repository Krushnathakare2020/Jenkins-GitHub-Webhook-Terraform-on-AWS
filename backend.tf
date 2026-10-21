terraform {
  backend "s3" {
    bucket       = "krushna-11-08-2004"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
