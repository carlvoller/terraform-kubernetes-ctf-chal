# lets create a namespace for our ctf challenges
data "kubernetes_namespace" "challenge_ns" {
  metadata {
    name = "ctf-chals"
  }
}

resource "kubernetes_deployment" "challenge_deployment" {
  depends_on = [
    docker_registry_image.challenge_published, docker_image.chal, docker_registry_image.healthcheck_published
  ]
  metadata {
    name      = "${var.name}-deploy"
    namespace = data.kubernetes_namespace.challenge_ns.metadata[0].name
    labels    = {
      app = var.name
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = var.name
      }
    }
    template {
      metadata {
        labels = {
          app = var.name
        }
        # required to mount things in most clouds
        annotations = {
          "container.apparmor.security.beta.kubernetes.io/challenge" : "unconfined"
        }
      }
      spec {
        container {
          name  = "challenge"
          image = local.published_image_name
          port {
            container_port = 1337
          }
          # this is the most restrictive context that still allows nsjail to run
          security_context {
            read_only_root_filesystem = true
            capabilities {
              drop = ["ALL"]
              add  = local.k8s_capabilities
            }
          }
          // both the liveness probe and the readiness probe are part of the healthcheck
          dynamic liveness_probe {
            // we use dynamic to include the healthcheck conditionally
            for_each = var.healthcheck ? [1] : []
            content {
              http_get {
                path = "/"
                port = 21337
              }
              failure_threshold     = 2
              initial_delay_seconds = 45
              timeout_seconds       = 3
              period_seconds        = 30
            }
          }
          dynamic readiness_probe {
            // we use dynamic to include the healthcheck conditionally
            for_each = var.healthcheck ? [1] : []
            content {
              http_get {
                path = "/"
                port = 21337
              }
              initial_delay_seconds = 5
              timeout_seconds       = 3
              period_seconds        = 5
            }
          }
        }
        dynamic container {
          // we use dynamic to include the healthcheck conditionally
          for_each = var.healthcheck ? [1] : []
          content {
            name  = "healthcheck"
            image = local.published_healthcheck_image_name
            resources {
              limits = {
                cpu = "1000m"
              }
              requests = {
                cpu = "50m"
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "challenge_autoscaler" {
  # only create the autoscaler if necessary
  count      = var.max_replicas > var.min_replicas ? 1 : 0
  depends_on = [kubernetes_deployment.challenge_deployment]
  metadata {
    name      = "${var.name}-autoscaler"
    namespace = data.kubernetes_namespace.challenge_ns.metadata[0].name
  }
  spec {
    target_cpu_utilization_percentage = var.target_utilization
    min_replicas                      = var.min_replicas
    max_replicas                      = var.max_replicas
    scale_target_ref {
      kind = "Deployment"
      name = "${var.name}-deploy"
    }
  }
}

resource "kubernetes_service" "challenge_service" {
  depends_on = [kubernetes_deployment.challenge_deployment, docker_image.chal]
  metadata {
    name      = "${var.name}-service"
    namespace = data.kubernetes_namespace.challenge_ns.metadata[0].name
    labels    = {
      app = var.name
    }
  }
  spec {
    type = "LoadBalancer"
    port {
      port        = local.k8s_port
      protocol    = "TCP"
      target_port = 1337
    }
    selector = {
      app = var.name
    }
  }
}
