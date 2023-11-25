provider "helm" {
  kubernetes {
    host                   = yandex_kubernetes_cluster.k8s-zonal.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.k8s-zonal.master[0].cluster_ca_certificate
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}




locals {
  jenkins_values = {
    "controller" = {
      "hostName"  = local.dns_domain_jenkins
      "jenkinsAdminEmail" = local.email
      "JCasC" = {

        "authorizationStrategy" = <<-EOT
          loggedInUsersCanDoAnything:
            allowAnonymousRead: false
          EOT
        "configScripts" = {
          "jenkins-configuration" = <<-EOT
          jenkins:
            systemMessage: This Jenkins is configured and managed 'as code' by Managed Cloud team.
          EOT
          "job-config" = yamlencode({
            jobs = [
                    { script = file("${path.module}/job0.groovy") },
            ]
          })
          "unclassified" =  <<-EOT
            unclassified:
              mailer:
                smtpHost: smtp.yandex.ru
                smtpPort: 465
                useSsl: true
                authentication:
                  username: ${local.email}
                  password: ${local.email_password}
            EOT
          "views"                 = <<-EOT
              jenkins:
                views:
                  - all:
                      name: "all"
                  - list:
                      columns:
                      - "status"
                      - "weather"
                      - "jobName"
                      - "lastSuccess"
                      - "lastFailure"
                      - "lastDuration"
                      - "buildButton"
                      jobNames:
                      - "job1"
                      name: "stage"
                viewsTabBar: "standard"
          EOT
        }
        "securityRealm" = <<-EOT
          local:
            allowsSignup: false
            users:
              - id: "admin"
                password: "${local.password}"
        EOT
      }
      "additionalPlugins" = [
        "job-dsl:1.81",
        "build-timeout:1.21",
        "timestamper:1.18",
        "permissive-script-security:0.7",
        "ansicolor:1.0.2"
      ]
      "imagePullPolicy" = "IfNotPresent"
      "ingress" = {
        "annotations" = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
        "apiVersion"       = "networking.k8s.io/v1"
        "enabled"          = true
        "hostName"         = local.dns_domain_jenkins
        "ingressClassName" = "nginx"
        "tls" = [
          {
            "hosts" = [
              local.dns_domain_jenkins,
            ]
            "secretName" = "jenkins-tls"
          },
        ]

      }
      "javaOpts"                     = "-Dpermissive-script-security.enabled=no_security"
      "numExecutors"                 = 1
      "adminPassword"                = "strongstrongpassword"
      "enableRawHtmlMarkupFormatter" = true
      "runAsUser"                    = 0
      "runAsGroup"                   = 0
      "containerSecurityContext" = {
        "runAsUser"              = 0
        "runAsGroup"             = 0
        "readOnlyRootFilesystem" = false
      }
      "lifecycle" = {
        "postStart" = {
          "exec" = {
            "command" = [
              "/bin/bash",
              "-c",
              "apt update && apt install -y jq",
            ]
          }
        }
      }
    }
  }
  password = file("${path.module}/.password")
  email="skberkanota@yandex.ru"
  email_password = file("${path.module}/.email_password")
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.2.1"
  wait       = true
  depends_on = [
    yandex_kubernetes_node_group.k8s_default_node_group
  ]
  set {
    name  = "controller.service.loadBalancerIP"
    value = yandex_vpc_address.addr.external_ipv4_address[0].address
  }
}

resource "helm_release" "cert-manager" {
  name             = "jenkins-certs"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.9.1"
  wait             = true
  depends_on = [
    yandex_kubernetes_node_group.k8s_default_node_group
  ]
  set {
    name  = "installCRDs"
    value = true
  }
}

resource "local_file" "inventory_yml" {
  content = templatefile("ClusterIssuer.yaml.tpl",
    {
      email_letsencrypt = local.email
    }
  )
  depends_on = [
    helm_release.cert-manager
  ]
  filename = "ClusterIssuer.yaml"
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  wait             = true
  version          = "4.8.3"
  depends_on = [
    yandex_kubernetes_node_group.k8s_default_node_group
  ]
  values = [
    #file("${path.module}/jenkins-values-google-login.yaml")
      yamlencode(local.jenkins_values)
  ]

}