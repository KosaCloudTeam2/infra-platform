project_name      = "cloud-infra-dev"
aws_region        = "ap-northeast-2"
github_repository = "OWNER/REPO"
container_port    = 8080
health_check_path = "/health"
task_cpu          = 256
task_memory       = 512
desired_count     = 2
image_tag         = "latest"
app_environment   = {}
app_secrets       = {}
db_instance_type  = "t3.small"
proxysql_count    = 1
db_node_count     = 3
db_volume_size    = 40

# 13일 MVP 기본값은 false.
# ProxySQL 고가용성을 시연하려면 proxysql_count = 2로 올리고 true로 변경한다.
enable_proxysql_internal_nlb = false
