#!/bin/bash
#
# Copyright (c) 2019 hankei6km
# Licensed under the MIT License. See LICENSE in the project root.

set -eu

USER_IN_CONTAINER="1000"
CONTAINER_NAME=""
SSH_ORIGINAL_COMMAND=""

function _usage {
  printf "Usage: %s: [-u USER(default:1000)] CONTAINER [SSH_ORIGINAL_COMMAND]\n" "$(basename "$0")"
}

while getopts u: FLAG ; do
  case "${FLAG}" in
    u) USER_IN_CONTAINER="${OPTARG}";;
    *) _usage ; exit 1;;
  esac
done

shift "$((OPTIND - 1))"
ARGS=( "${@}" )
if [ "${#ARGS[@]}" -eq 0 ] ; then
  _usage
  exit 1
fi
CONTAINER_NAME="${ARGS[0]}"
SSH_ORIGINAL_COMMAND=""
if [ "${#ARGS[@]}" -gt 1 ] ; then
  SSH_ORIGINAL_COMMAND="${ARGS[1]}"
fi

if [ -z "${CONTAINER_NAME}" ] ; then
  _usage; exit 1
fi


if [ -n "${SSH_ORIGINAL_COMMAND}" ] ; then
  docker exec -i -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash --noprofile --norc -c "${SSH_ORIGINAL_COMMAND}"
  exit "${?}"
fi


SEM_ID_REQ="github.com/hankei6km/vscode-remote-forwarder/run/req"


DIR_NAME="$(dirname "$0")"
RUN_PATH="${DIR_NAME}/run"

FIFO_REQ="${RUN_PATH}/req"
if [ ! -p "${FIFO_REQ}" ] ; then
  printf "fifo not found: %s\n" "${FIFO_REQ}"
  exit 1
fi

RESP_ID="${$}"
RUN_RESP_PATH="${RUN_PATH}/${RESP_ID}"
FIFO_RESP="${RUN_RESP_PATH}/resp"
if [ -d "${RUN_RESP_PATH}" ] ; then
  rm -rf "${RUN_RESP_PATH:?}" 
fi
mkdir -m 700 "${RUN_RESP_PATH}" 

MSG_PATTERN="[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+==([0-9]+)=="
PORT_SUB="s/\([^=]\+\)==\([0-9]\+\)==/\2/"
MSG_ID_SUB="s/\([^=]\+\)==\([0-9]\+\)==/\1/"
ADDR_PATTERN="IP Address: "

function get_container_server_log {
  docker exec -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash --noprofile --norc -c 'head -n 40 $(ls --sort=time "${HOME}"/.vscode-remote/.*.log | head -n 1)' 
}

function get_container_addr_from_log {
  CONTAINER_ADDR=$(get_container_server_log | grep "${ADDR_PATTERN}" | head -n 1)
  echo "${CONTAINER_ADDR/${ADDR_PATTERN}/}"
}

function request_forward {
  if read -r MSG_LINE ; then
    PORT=$(echo "${MSG_LINE}" | sed -e "${PORT_SUB}")
    MSG_ID=$(echo "${MSG_LINE}" | sed -e "${MSG_ID_SUB}")
    ADDR="$(get_container_addr_from_log)"
    # echo "${PORT}" "${ADDR}:${PORT}"  "${FIFO_REQ}"

    if [ ! -p "${FIFO_RESP}" ] ; then
      mkfifo -m 600 "${FIFO_RESP}"
    fi

    sem --fg --id "${SEM_ID_REQ}" 'echo '"${RESP_ID} ${MSG_ID} ${ADDR}:${PORT}"' > '"${FIFO_REQ}"
  fi
}

function receive_response {
  if [ -p "${FIFO_RESP}" ] ; then
    head -n 1 "${FIFO_RESP}"
  fi
}

docker exec -i -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash --noprofile --norc | tee >(grep -E "${MSG_PATTERN}" | request_forward)  | grep --line-buffered -v -E "${MSG_PATTERN}"

receive_response

rm -rf "${RUN_RESP_PATH:?}"
