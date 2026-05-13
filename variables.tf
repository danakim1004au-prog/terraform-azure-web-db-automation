variable "db_admin_password" {
  description = "SQL Server 관리자 비밀번호"
  type        = string
  sensitive   = true # 터미널 로그에 비밀번호가 찍히지 않게 합니다.
}