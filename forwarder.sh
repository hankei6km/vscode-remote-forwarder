#!/bin/bash
#
# Copyright (c) 2019 hankei6km
# Licensed under the MIT License. See LICENSE in the project root.

set -eu
set -m

DIR_NAME="$(dirname "${0}")"
RUN_PATH="${DIR_NAME}/run"

MSG_PLACE_HOLDER="PORT"

LISTEN_TIMEOUT="30"


function cleanup {
  rm -rf "${RUN_PATH:?}"
}
if [ ! -d "${RUN_PATH}" ] ; then
  mkdir -m 700 "${RUN_PATH}" 
fi

trap cleanup TERM INT HUP

FIFO_REQ="${RUN_PATH}/req"
if [ ! -p "${FIFO_REQ}" ] ; then
  mkfifo -m 600 "${FIFO_REQ}"
fi

function _log {
      echo "[$(date)] ${1}"
}

function forward {
  (
    RESP_ID="${1}"
    MSG_TEMPLATE="${2}"
    CONNECT="${3}"

    socat "TCP-LISTEN:0,reuseaddr,fork" "TCP-CONNECT:${CONNECT}" &

    LISTEN_PID="${!}"
    if kill -0 "${LISTEN_PID}" 2> /dev/null ; then
      LISTEN_PORT="$(lsof -Pan -p ${LISTEN_PID} -i 2> /dev/null | tail -n1 | sed -e 's/.\+:\([0-9]\+\).*/\1/')"
    fi

    RUN_RESP_PATH="${RUN_PATH}/${RESP_ID}"
    FIFO_RESP="${RUN_RESP_PATH}/resp"
    if [ -n "${LISTEN_PORT}" ] ; then
      MSG="${MSG_TEMPLATE/${MSG_PLACE_HOLDER}/$LISTEN_PORT}"
      echo "${MSG}" > "${FIFO_RESP}"
        
      _log "forwading: ${MSG} ${CONNECT}"
      sleep "${LISTEN_TIMEOUT}"
      while lsof -i -n -P -sTCP:ESTABLISHED | grep ":${LISTEN_PORT}" > /dev/null ; do
        sleep "${LISTEN_TIMEOUT}"
      done
      kill "${LISTEN_PID}"
      _log  "closed: ${MSG} ${CONNECT}"

    else
      _log "failed: ${MSG_TEMPLATE}"
      echo "" > "${FIFO_RESP}"
    fi

  ) &
}

tail -f "${FIFO_REQ}" | while true ; do
  if read -r REQ_LINE ; then
    read -r -a ARGS <<< "${REQ_LINE}"
    RESP_ID="${ARGS[0]}"
    MSG_TEMPLATE="${ARGS[1]}"
    CONNECT="${ARGS[2]}"
    # echo  "RES_ID=${RESP_ID}" "MSG_TEMPLATE=${MSG_TEMPLATE}" "CONNECT=${CONNECT}"
    forward "${RESP_ID}" "${MSG_TEMPLATE}" "${CONNECT}"
  fi
done
