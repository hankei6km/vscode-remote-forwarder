#!/bin/bash
#
# Copyright (c) 2019 hankei6km
# Licensed under the MIT License. See LICENSE in the project root.

set -eu

DIR_NAME="$(dirname "$0")"
RUN_PATH="${DIR_NAME}/run"

MSG_PLACE_HOLDER="PORT"

# shellcheck disable=SC2016
SOURCE_FILE='${HOME}/.forwarder_env'
USER_IN_CONTAINER="1000"
CONTAINER_NAME=""
SSH_ORIGINAL_COMMAND=""

function _usage {
  printf "Usage: %s: [-s SOURCE_FILE(default:%s)][-u USER(default:%s)] CONTAINER [SSH_ORIGINAL_COMMAND]\n" \
    "$(basename "$0")" \
    "${SOURCE_FILE}" \
    "${USER_IN_CONTAINER}"
}

while getopts s:u: FLAG ; do
  case "${FLAG}" in
    s) SOURCE_FILE="${OPTARG}";;
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


if [ -n "${SSH_ORIGINAL_COMMAND}" ] && [ "${SSH_ORIGINAL_COMMAND}" != "bash" ] ; then
  # echo "${SSH_ORIGINAL_COMMAND}"
  docker exec -i -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash -c "${SSH_ORIGINAL_COMMAND}"
  exit "${?}"
fi


SEM_ID_REQ="github.com/hankei6km/vscode-remote-forwarder/run/req"


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

INSERT_SOURCE_FILE=""
if [ -n "${SOURCE_FILE}" ]; then
  INSERT_SOURCE_FILE='test -e "'"${SOURCE_FILE}"'" && source "'"${SOURCE_FILE}"'"'";\n"
fi

# ID に含まれる文字(https://www.freedesktop.org/software/systemd/man/os-release.html).
HOOK_PATTERN="^VSCH_LOGFILE=|[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+(==([0-9]+)){1}(==([0-9a-z._-]+)){1}=="

# shellcheck disable=SC2016
INSERT_ECHO='s/^\( *VSCH_LOGFILE=.*\)/\1 ; echo "VSCH_LOGFILE=\"${VSCH_LOGFILE}\""/'
# とりあえず Extension host agent listening だけを取り出す
# (webview server listening も転送する必要ある?)
PORT_SUB="s/\([^=]\+\)==\([0-9]\+\)\(==[0-9]\+\)\{0,1\}\(==[0-9a-z._-]\+\)\{0,1\}==/\2/"
MSG_TEMPLATE_SUB="s/==[0-9]\+==/==${MSG_PLACE_HOLDER}==/"
ADDR_PATTERN="IP Address: "

function get_container_server_log {
  docker exec -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash --noprofile --norc -c "head -n 40 '""${1}""'"
}

function get_container_addr_from_log {
  CONTAINER_ADDR=$(get_container_server_log "${1}" | grep "${ADDR_PATTERN}" | head -n 1)
  echo "${CONTAINER_ADDR/${ADDR_PATTERN}/}"
}

function request_forward {
  mapfile -t HOOKED_LINES
  if [ "${#HOOKED_LINES[@]}" -eq 2 ] ; then

    VSCH_LOGFILE="${HOOKED_LINES[0]#VSCH_LOGFILE=}"

    PORT=$(echo "${HOOKED_LINES[1]}" | sed -e "${PORT_SUB}")
    MSG_TEMPLATE=$(echo "${HOOKED_LINES[1]}" | sed -e "${MSG_TEMPLATE_SUB}")
    ADDR="$(get_container_addr_from_log "${VSCH_LOGFILE}" )"
    # echo "${PORT}" "${ADDR}:${PORT}"  "${FIFO_REQ}"

    if [ ! -p "${FIFO_RESP}" ] ; then
      mkfifo -m 600 "${FIFO_RESP}"
    fi

    sem --fg --id "${SEM_ID_REQ}" 'echo '"'""${RESP_ID} ${MSG_TEMPLATE} ${ADDR}:${PORT}""'"' > '"'""${FIFO_REQ}""'"

  fi
}

function receive_response {
  if [ -p "${FIFO_RESP}" ] ; then
    BUF=$(head -n 1 "${FIFO_RESP}")
    echo "${BUF}"
  fi
}

cat <(echo -ne "${INSERT_SOURCE_FILE}") - \
  | sed -e "${INSERT_ECHO}" \
    | docker exec -i -u "${USER_IN_CONTAINER}" "${CONTAINER_NAME}" bash --noprofile --norc | tee >(grep -E "${HOOK_PATTERN}" | request_forward)  | grep --line-buffered -v -E "${HOOK_PATTERN}"

receive_response

rm -rf "${RUN_RESP_PATH:?}"
