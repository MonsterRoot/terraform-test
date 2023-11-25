locals {
  token       = file("${path.module}/.token")
  cloud_id    = "b1g7kgb2uen6e59u5iim"
  folder_id   = "b1gl5mbs8d2a6a52kb85"
  k8s_version = "1.27"
  sa_name     = "admin"
  dns_domain_jenkins = "jenkins.rand0m.ru"

    kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${yandex_kubernetes_cluster.k8s-zonal.master[0].external_v4_endpoint}
    certificate-authority-data: ${base64encode(yandex_kubernetes_cluster.k8s-zonal.master[0].cluster_ca_certificate)}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: yc
  name: ycmk8s
current-context: ycmk8s
users:
- name: yc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: yc
      args:
      - k8s
      - create-token
KUBECONFIG
}
output "kubeconfig" {
  value = local.kubeconfig
}
output "ip_host" {
  value = "${yandex_vpc_address.addr.external_ipv4_address[0].address} ${local.dns_domain_jenkins}"
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}


provider "yandex" {
  folder_id = local.folder_id
  token     = local.token
  zone      = "ru-central1-a"
}

resource "yandex_kubernetes_cluster" "k8s-zonal" {
  name = "k8s-test-cluster-trevelline"
  description = "Kubernetes test cluster for treveline testjob"
  network_id = yandex_vpc_network.mynewnet.id
  master {
    version = local.k8s_version
    zonal {
      zone      = yandex_vpc_subnet.mysubnet.zone
      subnet_id = yandex_vpc_subnet.mysubnet.id
    }
    public_ip = true
  }
  service_account_id      = yandex_iam_service_account.myaccount.id
  node_service_account_id = yandex_iam_service_account.myaccount.id
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller,
    yandex_kms_symmetric_key.kms-key

  ]
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_vpc_network" "mynewnet" {
  name = "mynewnet"
}

resource "yandex_vpc_subnet" "mysubnet" {
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mynewnet.id
  depends_on = [yandex_vpc_network.mynewnet]
}

resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета. Примените правила только для групп узлов."
  network_id  = yandex_vpc_network.mynewnet.id
    ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера Managed Service for Kubernetes и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера Managed Service for Kubernetes и сервисов."
    v4_cidr_blocks = concat(yandex_vpc_subnet.mysubnet.v4_cidr_blocks)
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "k8s-nodes-http-access" {
  name        = "k8s-nodes-http-access"
  description = "Правила группы разрешают подключение к узлам кластера по SSH. Примените правила только для групп узлов."
  network_id  = yandex_vpc_network.mynewnet.id

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к узлам по http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к узлам по http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
}

resource "yandex_iam_service_account" "myaccount" {
  name        = local.sa_name
  description = "K8S zonal service account"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  # Сервисному аккаунту назначается роль "k8s.clusters.agent".
  folder_id = local.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  # Сервисному аккаунту назначается роль "vpc.publicAdmin".
  folder_id = local.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  # Сервисному аккаунту назначается роль "container-registry.images.puller".
  folder_id = local.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}

resource "yandex_resourcemanager_folder_iam_member" "admin" {
  folder_id = local.folder_id
  role      = "admin"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_dns_zone" "dns_domain" {
  name   = replace(local.dns_domain_jenkins, ".", "-")
  zone   = join("", [local.dns_domain_jenkins, "."])
  public = true
  private_networks = [yandex_vpc_network.mynewnet.id]
}

resource "yandex_vpc_address" "addr" {
  name = "static-ip"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_dns_recordset" "jenkins_dns_domain" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", [local.dns_domain_jenkins, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_kubernetes_node_group" "k8s_default_node_group" {
  cluster_id = yandex_kubernetes_cluster.k8s-zonal.id
  name       = "k8s-default-node-group"
  instance_template {
    name       = "{instance.zone_id}-{instance_group.id}-{instance.short_id}"
    platform_id = "standard-v2"
    network_acceleration_type = "standard"
    resources {
      core_fraction = 5
    }
    container_runtime {
     type = "containerd"
    }
    network_interface {
      nat = true
      subnet_ids = [yandex_vpc_subnet.mysubnet.id]
      security_group_ids = [
        yandex_vpc_security_group.k8s-public-services.id,
        yandex_vpc_security_group.k8s-nodes-http-access.id
      ]
    }
  }
  scale_policy {
    fixed_scale {
      size = 1
    }
  }
}
