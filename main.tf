# main.tf

# Configura o provedor Google Cloud
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# --- 1. REDE (VPC) ---
# Cria nossa VPC personalizada e segura
resource "google_compute_network" "vpc_segura" {
  name                    = "vpc-segura"
  auto_create_subnetworks = false # Prática de segurança crucial!
}

# Cria a sub-rede
resource "google_compute_subnetwork" "subnet_segura" {
  name          = "subnet-segura"
  ip_cidr_range = "10.0.1.0/24" # Um range de IP privado
  region        = var.gcp_region
  network       = google_compute_network.vpc_segura.id
}

# --- 2. REGRAS DE FIREWALL ---
# Por padrão, o GCP bloqueia toda a entrada. Vamos manter assim,
# exceto por duas regras cruciais:

# Regra 1: Permite que VMs dentro da rede conversem entre si
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc_segura.id
  
  allow {
    protocol = "all" # Permite todos os protocolos internamente
  }
  source_ranges = ["10.0.1.0/24"] # Apenas da nossa própria sub-rede
}

# Regra 2: Permite SSH APENAS do Google IAP (Identity-Aware Proxy)
# Este é o nosso "portão" Zero Trust.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc_segura.id
  
  allow {
    protocol = "tcp"
    ports    = ["22"] # Porta SSH
  }
  
  # IPs mágicos do Google. Isso diz: "Permita SSH apenas
  # se vier do serviço IAP do Google, que verifica a identidade."
  source_ranges = ["35.235.240.0/20"] 
  
  # Aplica esta regra apenas a VMs com a tag "allow-iap-ssh"
  target_tags = ["allow-iap-ssh"] 
}

# Regra 3: Permite que nossas VMs acessem a internet (para atualizações)
resource "google_compute_firewall" "allow_egress" {
  name    = "allow-egress-internet"
  network = google_compute_network.vpc_segura.id
  
  # Invertemos a direção para "SAÍDA"
  direction = "EGRESS" 
  
  allow {
    protocol = "all"
  }
  destination_ranges = ["0.0.0.0/0"] # Para qualquer lugar
}

# --- 3. VM (Bastion Host) ---
# Cria nossa VM do nível gratuito
resource "google_compute_instance" "bastion_host" {
  name         = "bastion-host"
  machine_type = "e2-micro" # Parte do "Always Free" do GCP
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  # Conecta a VM à nossa rede segura
  network_interface {
    network    = google_compute_network.vpc_segura.id
    subnetwork = google_compute_subnetwork.subnet_segura.id
    
    # IMPORTANTE: Nenhum "access_config" é definido,
    # o que significa que esta VM NÃO TEM IP PÚBLICO.
  }
  
  # Adiciona a tag que nossa regra de firewall IAP está procurando
  tags = ["allow-iap-ssh"]

  # Garante que a rede esteja pronta antes de tentar criar a VM
  depends_on = [
    google_compute_network.vpc_segura,
    google_compute_subnetwork.subnet_segura
  ]
}

# --- 4. POLÍTICAS DA ORGANIZAÇÃO (Policy as Code) ---

# Os blocos a seguir estão comentados porque esta conta de GCP
# não está vinculada a um Nó de Organização, causando um erro 403.
# Em um ambiente corporativo real, estes blocos seriam descomentados
# e aplicados para impor as "guardrails" de segurança.

/*
# Política 1: Desativa a criação de VMs com IPs públicos em todo o projeto
resource "google_project_organization_policy" "block_public_ip" {
  project    = var.gcp_project_id
  constraint = "compute.vmExternalIpAccess"

  boolean_policy {
    enforced = true
  }
}

# Política 2: Restringe a criação de recursos apenas para nossa região
resource "google_project_organization_policy" "restrict_locations" {
  project    = var.gcp_project_id
  constraint = "gcp.resourceLocations"

  list_policy {
    allow {
      # Permite apenas recursos em southamerica-east1
      values = ["in:southamerica-east1-locations"]
    }
  }
}
*/


# --- 5. SAÍDAS ---
# Mostra o nome da VM após a criação
output "vm_name" {
  value = google_compute_instance.bastion_host.name
}

output "vm_internal_ip" {
  value = google_compute_instance.bastion_host.network_interface[0].network_ip
}