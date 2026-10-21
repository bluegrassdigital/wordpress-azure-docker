# Standalone fallback: never combine this file with the publishing bake file.
# Build locally: docker buildx bake -f docker-bake.emergency.hcl --load
# The default is Azure's amd64; set PHP_SOURCE_PLATFORMS for multiarch OCI output.
variable "PHP_SOURCE_PLATFORMS" {
  default = "linux/amd64"
}

variable "EMERGENCY_IMAGE" {
  default = "wordpress-azure-emergency"
}

# Use a unique timestamp/commit ID when preparing images for publication.
variable "EMERGENCY_BUILD_ID" {
  default = "local"
}

group "default" {
  targets = ["emergency83", "emergency84"]
}

group "all" {
  targets = ["emergency83", "emergency84", "emergency83-dev", "emergency84-dev"]
}

target "source83" {
  context = "php-source/8.3"
  platforms = split(",", PHP_SOURCE_PLATFORMS)
  tags = ["wordpress-azure-php-source:8.3.36"]
}

target "source84" {
  context = "php-source/8.4"
  platforms = split(",", PHP_SOURCE_PLATFORMS)
  tags = ["wordpress-azure-php-source:8.4.27"]
}

target "emergency83" {
  context = "."
  target = "runtime"
  platforms = split(",", PHP_SOURCE_PLATFORMS)
  contexts = { php-base = "target:source83" }
  args = {
    PHP_BASE_IMAGE = "php-base"
    # Imagick 3.8.0: avoid the PECL archive endpoint that returned HTTP 500.
    IMAGICK_PACKAGE = "Imagick/imagick@555bf68b592a8d9d0a0a2f37d1256a8b6cf2d39e"
  }
  tags = ["${EMERGENCY_IMAGE}:8.3.36-emergency-source-${EMERGENCY_BUILD_ID}"]
}

target "emergency84" {
  inherits = ["emergency83"]
  contexts = { php-base = "target:source84" }
  tags = ["${EMERGENCY_IMAGE}:8.4.27-emergency-source-${EMERGENCY_BUILD_ID}"]
}

target "emergency83-dev" {
  inherits = ["emergency83"]
  target = "dev"
  tags = ["${EMERGENCY_IMAGE}:8.3.36-dev-emergency-source-${EMERGENCY_BUILD_ID}"]
}

target "emergency84-dev" {
  inherits = ["emergency84"]
  target = "dev"
  tags = ["${EMERGENCY_IMAGE}:8.4.27-dev-emergency-source-${EMERGENCY_BUILD_ID}"]
}
