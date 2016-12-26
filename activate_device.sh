#!/bin/sh

SERVICE_ID=$(docker exec otb uci show overthebox.me.service | awk -F "'" '{ print $2 }')
CMD="require('overthebox').confirm_service('${SERVICE_ID}')"
docker exec otb lua -e "${CMD}"
