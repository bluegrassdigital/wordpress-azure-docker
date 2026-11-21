variable "PHP_VERSIONS" {
  default = "8.3,8.4,8.5,8.6"
}

group "default" {
  targets = ["php"]
}

group "dev" {
  targets = ["php-dev"]
}

group "all" {
  targets = ["php", "php-dev"]
}

target "base" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
}

target "php" {
  inherits = ["base"]
  matrix   = { version = split(",", PHP_VERSIONS) }
  name     = "php${replace(version, ".", "")}"
  target   = "runtime"
  args     = { PHP_VERSION = version }
  tags = [
    "bluegrassdigital/wordpress-azure-sync:${version}-latest",
    "bluegrassdigital/wordpress-azure-sync:${version}-stable"
  ]
}

target "php-dev" {
  inherits = ["base"]
  matrix   = { version = split(",", PHP_VERSIONS) }
  name     = "php${replace(version, ".", "")}-dev"
  target   = "dev"
  args     = { PHP_VERSION = version }
  tags = [
    "bluegrassdigital/wordpress-azure-sync:${version}-dev-latest",
    "bluegrassdigital/wordpress-azure-sync:${version}-dev-stable"
  ]
}
