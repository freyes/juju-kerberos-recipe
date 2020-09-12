#!/bin/bash -eu

DATA="{
    \"auth\": {
        \"identity\": {
            \"methods\": [
                \"password\"
            ],
            \"password\": {
                \"user\": {
                    \"domain\": {
                        \"name\": \"${OS_DOMAIN_NAME}\"
                    },
                    \"name\": \"${OS_USERNAME}\",
                    \"password\": \"${OS_PASSWORD}\"
                }
            }
        },
        \"scope\": {
            \"project\": {
                \"domain\": {
                    \"name\": \"${OS_PROJECT_DOMAIN_NAME}\"
                },
                \"name\": \"${OS_PROJECT_NAME}\"
            }
        }
    }
}"

echo "$DATA" | curl -si -d @- -H "Content-type: application/json" ${OS_AUTH_URL}/auth/tokens | awk '/X-Subject-Token/ {print $2}'
