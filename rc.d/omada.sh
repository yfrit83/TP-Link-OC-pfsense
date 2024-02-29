#!/bin/sh

# REQUIRE: FILESYSTEMS
# REQUIRE: NETWORKING
# PROVIDE: omada

. /etc/rc.subr

NAME="omada"
rcvar="omada_enable"
start_cmd="omada_start"
stop_cmd="omada_stop"

load_rc_config ${NAME}

OMADA_HOME="/opt/tplink/EAPController"
LOG_DIR="${OMADA_HOME}/logs"
WORK_DIR="${OMADA_HOME}/work"
DATA_DIR="${OMADA_HOME}/data"
PROPERTY_DIR="${OMADA_HOME}/properties"
AUTOBACKUP_DIR="${DATA_DIR}/autobackup"
HTTP_PORT=${HTTP_PORT:-8088}

JRE_HOME="/usr/local/openjdk8/jre"

JAVA_TOOL="${JRE_HOME}/bin/java"
#JAVA_OPTS="-server -Xms128m -Xmx1024m -XX:MaxHeapFreeRatio=60 -XX:MinHeapFreeRatio=30  -XX:+HeapDumpOnOutOfMemoryError -Deap.home=${OMADA_HOME}"
JAVA_OPTS="-server -XX:MaxHeapFreeRatio=60 -XX:MinHeapFreeRatio=30  -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${LOG_DIR}/java_heapdump.hprof -Djava.awt.headless=true"
MAIN_CLASS="com.tplink.smb.omada.starter.OmadaLinuxMain"

PID_FILE="/var/run/${NAME}.pid"

JSVC_OPTS="${JSVC_OPTS}\
 -pidfile ${PID_FILE} \
 -home ${JRE_HOME} \
 -cp /usr/share/java/commons-daemon.jar:${OMADA_HOME}/lib/*:${OMADA_HOME}/properties \
 -outfile ${LOG_DIR}/startup.log \
 -errfile ${LOG_DIR}/startup.log \
 -procname ${NAME} \
 -showversion \
 ${JAVA_OPTS}"

# return: 1,running; 0, not running;

is_running() {
#    ps -U root -u root u | grep eap | grep -v grep >/dev/null
    [ -z "$(pgrep -f ${MAIN_CLASS})" ] && {
        return 0
    }

    return 1
}

[ ! -f ${PROPERTY_DIR}/omada.properties ] || HTTP_PORT=$(grep "^[^#;]" ${PROPERTY_DIR}/omada.properties | sed -n 's/manage.http.port=\([0-9]\+\)/\1/p' | sed -r 's/\r//')
HTTP_PORT=${HTTP_PORT:-8088}

#---------------------------------------------------

# return: 1,running; 0, not running;
is_in_service() {
    http_code=$(curl -I -m 10 -o /dev/null -s -w %{http_code} http://localhost:${HTTP_PORT}/actuator/linux/check)
    if [ "${http_code}" != "200" ]; then
        return 0
    else
        return 1
    fi
}

 # check whether jsvc requires -cwd option
${JSVC} -java-home ${JRE_HOME} -cwd / -help >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    JSVC_OPTS="${JSVC_OPTS} -cwd ${OMADA_HOME}/lib"
fi

omada_start()
{
  echo -n "Starting Omada Controller. Please wait.\n"
   [ -e "${LOG_DIR}" ] || {
        mkdir -m 755 ${LOG_DIR} 2>/dev/null
    }

    rm -f "${LOG_DIR}/startup.log"
    touch "${LOG_DIR}/startup.log" 2>/dev/null
    
    
    [ -e "$WORK_DIR" ] || {
        mkdir -m 755 ${WORK_DIR} 2>/dev/null
    }
    
    [ -e "$AUTOBACKUP_DIR" ] || {
        mkdir -m 755 ${AUTOBACKUP_DIR} 2>/dev/null
    }

    ${JAVA_TOOL} ${JSVC_OPTS} ${MAIN_CLASS} start
    
        count=0

    while true
    do
        is_in_service
        if  [ 1 == $? ]; then
            break
        else
            sleep 1
            echo -n "."
            count=`expr $count + 1`
            if [ $count -gt 300 ]; then
                break
            fi
        fi
    done

    echo "."

    is_in_service
    if  [ 1 == $? ]; then
        echo "Started successfully."
        echo You can visit http://localhost:${HTTP_PORT} on this host to manage the wireless network.
    else
        echo "Start failed."
    fi

}

omada_stop()
{

  is_running
    if  [ 0 == $? ]; then
        echo "Omada Controller not running."
        exit
    fi

    echo -n "Stopping Omada Controller "
    ${JSVC} ${JSVC_OPTS} -stop ${MAIN_CLASS} stop
    count=0

    while true
    do
        is_running
        if  [ 0 == $? ]; then
            break
        else
            sleep 1
            count=`expr $count + 1`
            echo -n "."
            if [ $count -gt 30 ]; then
                break
            fi
        fi
    done

    echo ""

    is_running
    if  [ 0 == $? ]; then
        echo "Stop successfully."

    else
        echo "Stop failed. going to kill it."
        pkill -f ${MAIN_CLASS}
    fi

    rm $PID_FILE

}

omada_status()
{
    is_running
    if  [ 0 == $? ]; then
        echo "${DESC} is not running."
    else
        echo "${DESC} is running. You can visit http://localhost:${HTTP_PORT} on this host to manage the wireless network."
    fi

}





run_rc_command "$1"
