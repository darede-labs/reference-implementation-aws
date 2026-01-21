module github.com/${{ values.gitHubOrg }}/${{ values.name }}

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/prometheus/client_golang v1.18.0
)
