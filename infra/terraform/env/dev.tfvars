project_name      = "cloud-infra-dev"
aws_region        = "ap-northeast-2"
github_repository = "OWNER/REPO"
container_port    = 8080
health_check_path = "/health"

# Docker Hub 이미지가 준비되면 실제 DOCKERHUB_USERNAME/cloud-infra-app:latest 형식으로 교체한다.
app_image            = "dockerhub-username/cloud-infra-app:latest"
app_instance_type    = "t3.micro"
app_min_size         = 0
app_desired_capacity = 1
app_max_size         = 2
app_environment      = {}
app_secrets          = {}

db_instance_type = "t3.small"
proxysql_count   = 1
db_node_count    = 3
db_volume_size   = 40

# 13일 MVP 기본값은 false.
# ProxySQL 고가용성을 시연하려면 proxysql_count = 2로 올리고 true로 변경한다.
enable_proxysql_internal_nlb = false
