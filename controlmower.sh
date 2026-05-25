#!/bin/bash

# script to control a Novabot mower connected to Opennova server.
# Usage: <start|stop|pause|resume|home|set> {[area] [cutterhigh], [[path angle] [Obstacle detection]}
# start mode needs input 
#       area map1, map10, map100, map11 (=map 1 and 10), map101 (map 1 and 100), map 111 (all 3 maps)
#          note: map0 is map1 , map1 is map10 map2 is map 100
#       cutterheight range 0..7. Formula: user_cm − 2. So 5 cm → 3, 6 cm → 4
# set needs input 
#       path angle, range 0-180
#       obstacle detection, 1, 2 or 3 (Low, medium, High)
#
#
# chenge next section to your situation
SERVER="192.168.x.x"
SERIAL="LFINxxxxxxxxx"
#  End change needed

URL="http://${SERVER}/api/dashboard/command/${SERIAL}"


MODE="$1"
AREA="$2"
CUTTERHIGH="$3"

if [ -z "$MODE" ]; then
    echo "Usage: $0 <start|stop|pause|resume|home|set> {[area] [cutterhigh], [[path angle] [Obstacle detection]}"
    exit 1
fi

send_payload() {
    local payload="$1"
    echo "Sending payload:"
    echo "$payload"
    curl -X POST "$URL" \
         -H "Content-Type: application/json" \
         -d "$payload"
}

case "$MODE" in
    start)
        if [ -z "$AREA" ] || [ -z "$CUTTERHIGH" ]; then
            echo "start requires: area and cutterhigh"
            exit 1
        fi

        CMD_NUM=$(date +%s)
        PAYLOAD=$(cat <<EOF
{
  "command": {
    "start_navigation": {
      "area": $AREA,
      "cutterhigh": $CUTTERHIGH,
      "cmd_num": $CMD_NUM
    }
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD"
        ;;

    stop)
        CMD_NUM=$(date +%s)
        PAYLOAD=$(cat <<EOF
{
  "command": {
    "stop": {
      "cmd_num": $CMD_NUM
    }
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD"
        ;;

    pause)
        CMD_NUM=$(date +%s)
        PAYLOAD=$(cat <<EOF
{
  "command": {
    "pause": {
      "cmd_num": $CMD_NUM
    }
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD"
        ;;

    resume)
        CMD_NUM=$(date +%s)
        PAYLOAD=$(cat <<EOF
{
  "command": {
    "resume_navigation": {
      "cmd_num": $CMD_NUM
    }
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD"
        ;;

    home)
        # Step 1: home
        CMD1=$(date +%s)
        PAYLOAD1=$(cat <<EOF
{
  "command": {
    "stop_navigation": {}
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD1"

        # 500 ms delay
        sleep 0.5

        # Step 2: home_continue
        CMD2=$(date +%s)
        PAYLOAD2=$(cat <<EOF
{
  "command": {
    "go_to_charge": {
      "cmd_num": $CMD2,
      "chargerpile": {"latitude":100,"longitude":100}
    }
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD2"
        ;;
    set)
        if [ -z "$AREA" ] || [ -z "$CUTTERHIGH" ]; then
            echo "set requires: path angle and obstacle detection"
            exit 1
        fi

        CMD_NUM=$(date +%s)
        PAYLOAD=$(cat <<EOF
{"command":{
  "set_para_info":{"sound":0,"headlight":0,"path_direction":$AREA,"obstacle_avoidance_sensitivity":$CUTTERHIGH,"manual_controller_v":2,"manual_controller_w":2}
  },
  "encrypt": false
}
EOF
)
        send_payload "$PAYLOAD"
        ;;

    *)
        echo "Unknown mode: $MODE"
        exit 1
        ;;
esac
