#!/usr/bin/env ruby
require "open3"
require "yaml"

overlay = File.expand_path(__dir__)
rendered, error, status = Open3.capture3("kubectl", "kustomize", overlay)
abort error unless status.success?
items = YAML.load_stream(rendered)
by_kind = items.group_by { |item| item.fetch("kind") }
fail "local dependency Service included" unless (by_kind.fetch("Service").map { |item| item.dig("metadata", "name") } & %w[db redis kafka]).empty?
fail "local Nginx ConfigMap included" if by_kind.fetch("ConfigMap").any? { |item| item.dig("metadata", "name") == "web-proxy" }

accounts = by_kind.fetch("ServiceAccount").to_h { |item| [item.dig("metadata", "name"), item] }
expected_accounts = %w[api worker closer db-prepare kafka-publisher kafka-audit kafka-projection web]
fail "KSA names changed" unless accounts.keys.sort == expected_accounts.sort
terraform_main = File.read(File.expand_path("../../../infra/terraform/modules/reference/main.tf", overlay))
secret_reader_list = terraform_main.match(/secret_readers\s*=\s*toset\(\[([^\]]+)\]\)/)&.captures&.first.to_s.scan(/"([^"]+)"/).flatten
fail "Terraform secret readers differ from runtime KSAs" unless secret_reader_list.sort == (expected_accounts - ["web"]).sort
fail "HMAC keyring IAM missing" unless terraform_main.include?('resource "google_secret_manager_secret" "idempotency_hmac_keyring"') &&
  terraform_main.include?('resource "google_secret_manager_secret_iam_member" "idempotency_hmac_keyring_read"')
config = by_kind.fetch("ConfigMap").find { |item| item.dig("metadata", "name") == "hammerfall-config" }
fail "HMAC keyring file not configured" unless config.dig("data", "IDEMPOTENCY_HMAC_KEYRING_FILE") == "/var/run/hammerfall-secrets/idempotency-hmac-keyring.json"
by_kind.fetch("SecretProviderClass").each do |secret_class|
  mounted = YAML.safe_load(secret_class.dig("spec", "parameters", "secrets"))
  expected = "projects/PROJECT_ID/secrets/hammerfall-reference-idempotency-hmac-keyring/versions/1"
  fail "HMAC keyring mount missing" unless mounted.any? { |entry| entry["resourceName"] == expected && entry["path"] == "idempotency-hmac-keyring.json" }
end
redis_reader_list = terraform_main.match(/redis_readers\s*=\s*toset\(\[([^\]]+)\]\)/)&.captures&.first.to_s.scan(/"([^"]+)"/).flatten
fail "Terraform Redis CA readers changed" unless redis_reader_list.sort == %w[api worker kafka-projection].sort
%w[kafka-publisher kafka-audit kafka-projection].each do |role|
  expected = "hf-reference-#{ { "kafka-publisher" => "kpub", "kafka-audit" => "kaudit", "kafka-projection" => "kproj" }.fetch(role) }@PROJECT_ID.iam.gserviceaccount.com"
  fail "Kafka KSA/GSA mismatch: #{role}" unless accounts.fetch(role).dig("metadata", "annotations", "iam.gke.io/gcp-service-account") == expected
end
fail "web received IAM annotation" if accounts.fetch("web").dig("metadata", "annotations")

deployments = by_kind.fetch("Deployment").to_h { |item| [item.dig("metadata", "name"), item] }
fail "application workload count changed" unless deployments.length == 9
account_by_workload = {
  "api" => "api", "auction-closer" => "closer", "kafka-audit-consumer" => "kafka-audit",
  "kafka-outbox-publisher" => "kafka-publisher", "kafka-projection-consumer" => "kafka-projection",
  "outbox-publisher" => "worker", "reconciliation-scheduler" => "worker", "sidekiq" => "worker", "web" => "web"
}
fail "workload names changed" unless deployments.keys.sort == account_by_workload.keys.sort
deployments.each do |name, deployment|
  pod = deployment.fetch("spec").fetch("template").fetch("spec")
  account = pod.fetch("serviceAccountName")
  fail "wrong KSA: #{name}" unless account == account_by_workload.fetch(name)
  containers = pod.fetch("containers")
  if name == "web"
    fail "web proxy/secret leaked" unless containers.map { |c| c.fetch("name") } == ["web"] && !pod.key?("volumes")
    next
  end
  fail "local DB secret leaked: #{name}" if containers.first.fetch("envFrom").any? { |ref| ref.key?("secretRef") }
  volume = pod.fetch("volumes").find { |entry| entry["name"] == "runtime-secrets" }
  fail "CSI mount missing: #{name}" unless volume.dig("csi", "driver") == "secrets-store-gke.csi.k8s.io" && volume.dig("csi", "readOnly")
  expected_secret_class = redis_reader_list.include?(account) ? "hammerfall-db-redis-gke" : "hammerfall-db-gke"
  fail "wrong secret exposure: #{name}" unless volume.dig("csi", "volumeAttributes", "secretProviderClass") == expected_secret_class
  fail "secret mount writable: #{name}" unless containers.first.fetch("volumeMounts").any? { |mount| mount["name"] == "runtime-secrets" && mount["readOnly"] }
  if name.start_with?("kafka-")
    fail "Kafka auth sidecar missing: #{name}" unless containers.map { |c| c["name"] }.include?("kafka-auth")
    fail "Kafka cloud mode missing: #{name}" unless containers.first.fetch("env").any? { |entry| entry["name"] == "KAFKA_AUTH_MODE" && entry["value"] == "google_oidc" }
  end
end

job = by_kind.fetch("Job").find { |item| item.dig("metadata", "name") == "db-prepare" }
fail "db-prepare missing" unless job
job_pod = job.fetch("spec").fetch("template").fetch("spec")
fail "db-prepare KSA/secret mismatch" unless job_pod.fetch("serviceAccountName") == "db-prepare" &&
  job_pod.fetch("volumes").find { |entry| entry["name"] == "runtime-secrets" }
    .dig("csi", "volumeAttributes", "secretProviderClass") == "hammerfall-db-gke"

routes = by_kind.fetch("HTTPRoute")
https = routes.find { |route| route.dig("metadata", "name") == "hammerfall-https" }
rules = https.fetch("spec").fetch("rules")
fail "edge routing changed" unless rules.map { |rule| [rule.dig("matches", 0, "path", "value"), rule.dig("backendRefs", 0, "name")] } == [["/api", "api"], ["/cable", "api"], ["/", "web"]]
health = by_kind.fetch("HealthCheckPolicy").to_h { |item| [item.dig("spec", "targetRef", "name"), item] }
fail "API health must use /ready" unless health.fetch("api").dig("spec", "default", "config", "httpHealthCheck", "requestPath") == "/ready"
fail "web health must use /" unless health.fetch("web").dig("spec", "default", "config", "httpHealthCheck", "requestPath") == "/"

puts "GCP overlay: #{items.length} resources, workloads/identity/mounts/routes/health checked"
