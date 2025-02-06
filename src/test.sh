#!/bin/bash

odate() {
        date '+%Y.%m.%d %H:%M:%S'
}
### THIS PART IS NEEDED  To MOVE MONITORIN OUT OF SCIPT
#@Release Notes
#On POS HOST 2 change SERVERNAME to POSHOST-2
SERVERNAME="POSHOST-2"
SENDER="NO_REPLY@phost-2.sbcore.net"
API_KEY="BwavYaYI.LfmMe8sWEoeN-yCiW9P8Y6acjL5IMDNZzqo"
URL="https://alerts-api.swedbank.net/api/v1/alerts"
ENVIRONMENT="production"

CI="$(hostname)"
LOG_FILE=""

load_so_ehi () {
CC=$1

    if [ "$CC" == "LT" ]
        then SO="Pos channel Lithuania"
             EHI="KB0023171"
    elif [ "$CC" == "LV" ]
        then SO="Pos channel Latvia"
             EHI="KB0023170"
    elif [ "$CC" == "EE" ]
        then SO="Pos channel Estonia"
             EHI="KB0023169"
    else 
        echo "Country not found. Unable to set Service Offering and EHI"
        EHI=
    fi
}

send_event() {
    CC=$1
    MONTEXT=$2
    
    RECIEVER="pbpos@swedbank.lt"
    SEVERITY="MAJOR"
    PROCESS="ONLINE"
    CURST="ERROR"
    AUTO_CREATE_INCIDENT=true
    msg="${CC} POS have errors: "
    txt="$msg $MONTEXT"
    
    load_so_ehi "${CC}"
    
    echo "$MONTEXT" | /usr/bin/mailx -s "!!! $txt !!!" -r $SENDER $RECIEVER

    CURLREZULT=$(curl --insecure -X POST ${URL} -H 'Authorization: API-Key '${API_KEY}'' -H 'Content-Type: application/json' -d '{
        "severity": "'"$SEVERITY"'",
        "resource": "'"${CC}"'_'"${SERVERNAME}"'_'"${PROCESS}"'",
        "event": "'"$CURST"'",
        "environment": "'"$ENVIRONMENT"'",
        "service": ["'"$SO"'"],
        "message": "'"${MONTEXT} Call PB Acquiring."'",
        "attributes.ci.name": "'"${CI%%.*}"'",
        "attributes.snap.ehi": "'"${EHI}"'",    
        "attributes.snap.firstLine": "Operations Center",
        "attributes.snap.secondLine": "Cards Acquiring Baltics",
        "attributes.snap.incident.auto_create": '${AUTO_CREATE_INCIDENT}'
    }')

    ID=$( echo "$CURLREZULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" )

    echo "$ID"
}


send_error() {
SEVERITY=$1
PROCESS=$2
CC=$3
STATUS=$4 # CURRENT aka OLD STATUS
CURST=$5 # NEW  aka CURRENT STATUS

RECIEVER=$MAILUSER

load_so_ehi "${CC}"

if [ "$CURST" == "CRASH" ]
then     
    MONTEXT="${CC}_POS_${SERVERNAME}.$PROCESS process crashed (no process with given pid)"
    MAILTEXT="[${CC}]-[$CURST]-[${PROCESS}]-[${SERVERNAME}] crashed"
    AUTO_CREATE_INCIDENT=true
fi

if [ "$CURST" == "DOWN" ]
then
    if [ "$WHATMON" == "PORT" ]
    then
        MONTEXT="${CC}_POS_${SERVERNAME}.Port $PROCESS is down"
        MAILTEXT="[${CC}]-[$CURST]-[PORT ${PROCESS}]-[${SERVERNAME}] down"
    else
        MONTEXT="${CC}_POS_${SERVERNAME}.$PROCESS process is down (no pid file found)"
        MAILTEXT="[${CC}]-[$CURST]-[${PROCESS}]-[${SERVERNAME}] down"
    fi
    AUTO_CREATE_INCIDENT=true
fi

if [ "$CURST" == "UP" ]
then
    if [ "$WHATMON" == "PORT" ]
    then
        MONTEXT="${CC}_POS_${SERVERNAME}.Port $PROCESS is up"
        MAILTEXT="[${CC}]-[$CURST]-[PORT ${PROCESS}]-[${SERVERNAME}] up"
    else
        MONTEXT="${CC}_POS_${SERVERNAME}.$PROCESS process is up"
        MAILTEXT="[${CC}]-[$CURST]-[${PROCESS}]-[${SERVERNAME}] up"
    fi
    AUTO_CREATE_INCIDENT=false
fi

if [ "$SEVERITY" == "CRITICAL" ]
then     
    MONTEXT="${CC}_POS_${SERVERNAME} URGENT!!! POSHOST was not restarted after multiple attempts"
    MAILTEXT="[${CC}]-[$CURST]-[POSHOST]-[${SERVERNAME}]  was not restarted after multiple attempts"
    AUTO_CREATE_INCIDENT=true
fi

tail -20 "${HOME}"/"${CC}"/log/"${PROCESS}".log | /usr/bin/mailx -s "$MAILTEXT" -r $SENDER  "$RECIEVER" >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log 
echo "tail -20 ${HOME}/${CC}/log/${PROCESS}.log | /usr/bin/mailx -s \"$MAILTEXT\" -r $SENDER  $RECIEVER " >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log 

CURLREZULT=$(curl --insecure -X POST ${URL} -H 'Authorization: API-Key '${API_KEY}'' -H 'Content-Type: application/json' -d '{
    "severity": "'"$SEVERITY"'",
    "resource": "'"${CC}"'_'"${SERVERNAME}"'_'"${PROCESS}"'",
    "event": "'"$CURST"'",
    "environment": "'"$ENVIRONMENT"'",
    "service": ["'"$SO"'"],
    "message": "'"$MONTEXT. Call PB Acquiring."'",
    "attributes.ci.name": "'"${CI%%.*}"'",
    "attributes.snap.ehi": "'"${EHI}"'",    
    "attributes.snap.firstLine": "Operations Center",
    "attributes.snap.secondLine": "Cards Acquiring Baltics",
    "attributes.snap.incident.auto_create": '"${AUTO_CREATE_INCIDENT}"'
}')

echo -e "$CURLREZULT" >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log
echo -e "\n" >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log

if [ "${CURST}" != "UP" ]; then
    ID=$( echo "$CURLREZULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" )

    echo "$ID"
else
    echo ""
fi

}

# Update snap incident with status close
update_incident() {

  INCIDENT_ID=$1
  CC=$2
  local currenttime
  currenttime=$(date +%H:%M)

  if [[ "$currenttime" > "22:00" ]] || [[ "$currenttime" < "06:00" ]]; then
      curl --insecure -X PUT ${URL}/"${INCIDENT_ID}" -H 'Authorization: API-Key '${API_KEY}'' -H 'Content-Type: application/json' -d '{
          "status": "closed",
          "severity": "minor"
      }' >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log
      echo -e "\n" >> "$HOME"/"$CC"/log/"${SCRIPTNAME}".log
  fi
}

check_status_and_send_event() {

  MONDIR=$1
  FILE_NAME=$2
  STATUS=$3
  CC=$4
  MESSAGE=$5
  FILE_NAME="${FILE_NAME}_get_txns.down"

    if [ -f "${MONDIR}"/"${FILE_NAME}" ] && [[ $(ls -1 "${MONDIR}"/*get_txns.down | wc -l) -gt 1 ]] && [ "${STATUS}" == 'OK' ] ; then
    rm "${MONDIR}"/"${FILE_NAME}"

    else
       if [ -f "${MONDIR}"/"${FILE_NAME}" ] && [[ "${STATUS}" == 'OK' ]]; then
          if [[ $((($(date +%s) - $(date -r "${MONDIR}"/"${FILE_NAME}" +%s))/60)) -lt 5 ]]
                 then
                 IN_ID=$(<"${MONDIR}"/"${FILE_NAME}")
                 update_incident "${IN_ID}" "${CC}"
          fi
          rm "${MONDIR}"/"${FILE_NAME}"
       fi
    fi


    if [ ! -f "${MONDIR}"/"${FILE_NAME}" ] && [ "${STATUS}" == 'DOWN' ] ; then

      local INCIDENT_ID
      INCIDENT_ID=$(send_event "${CC}" "${MESSAGE}")
      echo "$INCIDENT_ID" > "${MONDIR}"/"${FILE_NAME}"

    fi

}

log_line() {
  local message="$1"
  echo "$(odate) $message" >>"$LOG_FILE"
}

send_alert() {
    PROCESS=$1
    MESSAGE=$2

    RECIEVER="pbpos@swedbank.lt"

    set_service_offering

    if [ $# -eq 2 ]; then
        load_so_ehi "${PROGRAM_COUNTRY}"
    elif [ $# -eq 3 ]; then
        EHI=$3
    fi

    curl --insecure -X POST ${URL} -H 'Authorization: API-Key '${API_KEY}'' -H 'Content-Type: application/json' -d '{
      "severity": "minor",
      "resource": "'"${PROGRAM_COUNTRY}"'_'${SERVERNAME}'_'"${PROCESS}"'",
      "event": "'"${PROCESS}"'",
      "environment": "'${ENVIRONMENT}'",
      "value": "ERROR",
      "message": "'"${PROGRAM_COUNTRY}"' '"${PROCESS}"' '"${MESSAGE}"'",
      "service": [
          "'"${SERVICE_OFFERING}"'"
      ],
      "attributes": {
          "snap": {
              "ehi": "'"${EHI}"'",
              "incident": {
                  "first_line": "Operations Center",
                  "second_line": "Cards Acquiring Baltics",
                  "auto_create": true
              }
          },
          "email": {
              "to": "'${RECIEVER}'"
          }
      }
    }' >> "${LOG}"
}

set_service_offering () {
  case "$PROGRAM_COUNTRY" in
      "LT")     SERVICE_OFFERING="Pos channel Lithuania" ;;
      "LV")     SERVICE_OFFERING="Pos channel Latvia" ;;
      "EE")     SERVICE_OFFERING="Pos channel Estonia" ;;
      *)        SERVICE_OFFERING="Pos channel Estonia"
                log_line ERROR "Unknown program country. Setting default service offering: Pos channel Estonia" ;;
  esac
}
