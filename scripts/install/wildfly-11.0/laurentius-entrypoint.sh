#!/bin/sh
# laurentius-entrypoint.sh - first-run initializer + normal startup
set -e

DB_DIALECT=${DB_DIALECT:-org.hibernate.dialect.H2Dialect}
DB_INI_ACTION=${DB_INI_ACTION:-create}
DB_RUNTIME_ACTION=${DB_RUNTIME_ACTION:-none}
DB_FILE_PREFIX=${DB_FILE_PREFIX:-$WILDFLY_HOME/standalone/data/laurentius-db}
DB_VERIFY_TABLE=${DB_VERIFY_TABLE:-LAU_SETTINGS}
LISTEN_MASK=${LISTEN_MASK:-0.0.0.0}
WILDFLY_HOME=${WILDFLY_HOME:-/opt/jboss/wildfly}
LAU_HOME=${LAU_HOME:-$WILDFLY_HOME/standalone/data/laurentius-home}
LAU_AUTO_INIT=${LAU_AUTO_INIT:-true}
INIT_MARKER="$LAU_HOME/.initialized"
SEED_SRC=${LAU_SEED_DIR:-$WILDFLY_HOME/laurentius-home-template}
H2_JAR=${H2_JAR:-}
LOG_FILE=${ENTRYPOINT_LOG:-$WILDFLY_HOME/standalone/log/entrypoint.log}

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s | %s\n' "$timestamp" "$*" | tee -a "$LOG_FILE"
}

schema_ready() {
  local h2_jar
  local java_bin
  if [ -x "$JAVA_HOME/bin/java" ]; then
    java_bin="$JAVA_HOME/bin/java"
  else
    java_bin=java
  fi

  if [ -n "$H2_JAR" ] && [ -f "$H2_JAR" ]; then
    h2_jar="$H2_JAR"
  else
    for candidate in "$WILDFLY_HOME"/modules/system/layers/base/com/h2database/h2/main/*.jar; do
      if [ -f "$candidate" ]; then
        h2_jar="$candidate"
        break
      fi
    done
    if [ -z "$h2_jar" ]; then
      return 1
    fi
  fi

  local output
  output=$(run_as_jboss "$java_bin" -cp "$h2_jar" org.h2.tools.Shell \
    -url "jdbc:h2:file:${DB_FILE_PREFIX}" \
    -user laurentius \
    -password laurentius \
    -sql "SELECT 1 FROM $DB_VERIFY_TABLE LIMIT 1" 2>&1 || true)
  printf '%s\n' "$output" | tee -a "$LOG_FILE" >/dev/null

  if printf '%s\n' "$output" | grep -qi 'Table \"'; then
    return 1
  fi
  if printf '%s\n' "$output" | grep -qi 'Syntax error'; then
    return 1
  fi
  return 0
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_as_jboss() {
  if [ "$(id -u)" -eq 0 ]; then
    if command_exists runuser; then
      runuser -u jboss -- "$@"
    else
      su -s /bin/sh jboss -c "$*"
    fi
  else
    "$@"
  fi
}

run_bg_as_jboss() {
  if [ "$(id -u)" -eq 0 ]; then
    if command_exists runuser; then
      runuser -u jboss -- "$@" &
    else
      su -s /bin/sh jboss -c "$*" &
    fi
  else
    "$@" &
  fi
}

# Ensure directories exist and have permissive perms for jboss
mkdir -p "$LAU_HOME"
mkdir -p "$WILDFLY_HOME/standalone/log"
if [ "$(id -u)" -eq 0 ]; then
  chown -R jboss:jboss "$LAU_HOME" "$WILDFLY_HOME/standalone/log" || true
fi
chmod -R a+rwX "$LAU_HOME" "$WILDFLY_HOME/standalone/log" || true

# Seed Laurentius home when mounting an empty volume
if [ -d "$SEED_SRC" ]; then
  if [ -z "$(find "$LAU_HOME" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log "Seeding Laurentius home from $SEED_SRC..."
    cp -a "$SEED_SRC/." "$LAU_HOME/"
    if [ "$(id -u)" -eq 0 ]; then
      chown -R jboss:jboss "$LAU_HOME" || true
    fi
  fi
fi

LAU_OPTS="-c standalone-laurentius.xml -Dlaurentius.home=$LAU_HOME/ -Dlaurentius.init.dir=$LAU_HOME/conf/init"
LAU_RUNTIME_OPTS="$LAU_OPTS -Dlaurentius.hibernate.hbm2ddl.auto=$DB_RUNTIME_ACTION -Dlaurentius.hibernate.dialect=$DB_DIALECT -Dhibernate.dialect=$DB_DIALECT"
if [ -n "$LAU_DOMAIN" ]; then
  LAU_RUNTIME_OPTS="$LAU_RUNTIME_OPTS -Dlaurentius.domain=$LAU_DOMAIN"
fi

if [ -f "$INIT_MARKER" ] && [ "x$LAU_AUTO_INIT" != "xfalse" ]; then
  if ! schema_ready; then
    log "Initialization marker exists but schema check failed; removing marker to rerun init."
    rm -f "$INIT_MARKER" || true
  fi
fi

if [ ! -f "$INIT_MARKER" ] && [ "x$LAU_AUTO_INIT" != "xfalse" ]; then
  if [ -z "$LAU_DOMAIN" ]; then
    log "LAU_DOMAIN not set; skipping auto-init"
  else
    log "Performing first-run initialization..."

    # Reset server.log so error checks only look at the current init run
    if [ -f "$WILDFLY_HOME/standalone/log/server.log" ]; then
      rm -f "$WILDFLY_HOME/standalone/log/server.log" || true
    fi

    case "$DB_INI_ACTION" in
      create|create-drop|drop-and-create)
        log "Removing existing database files ($DB_FILE_PREFIX.*) before schema creation."
        rm -f "${DB_FILE_PREFIX}".* || true
        ;;
    esac

    INIT_OPTS="$LAU_OPTS -Dlaurentius.hibernate.hbm2ddl.auto=$DB_INI_ACTION -Dlaurentius.hibernate.dialect=$DB_DIALECT -Dhibernate.dialect=$DB_DIALECT -Dlaurentius.init=true"
    if [ -n "$LAU_DOMAIN" ]; then
      INIT_OPTS="$INIT_OPTS -Dlaurentius.domain=$LAU_DOMAIN"
    fi

    log "Running first-run init: $WILDFLY_HOME/bin/standalone.sh $INIT_OPTS -b $LISTEN_MASK -bmanagement $LISTEN_MASK"
    run_bg_as_jboss "$WILDFLY_HOME/bin/standalone.sh" $INIT_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"
    WF_PID=$!

    WAIT_SEC=0
    MAX_WAIT=180
    log "Waiting for server to start for initialization..."
    while :; do
      if grep -q "WFLYSRV0025: WildFly .* started" "$WILDFLY_HOME/standalone/log/server.log" 2>/dev/null; then
        break
      fi
      if ! kill -0 "$WF_PID" 2>/dev/null; then
        log "Initialization server exited before startup completed."
        exit 1
      fi
      sleep 1
      WAIT_SEC=$((WAIT_SEC + 1))
      if [ "$WAIT_SEC" -ge "$MAX_WAIT" ]; then
        log "Timeout waiting for server to start. Aborting init."
        kill "$WF_PID" || true
        exit 1
      fi
    done

    sleep 5
    log "Shutting down initialization server..."
    run_as_jboss "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --controller=localhost:9990 --command=":shutdown" >/dev/null 2>&1 || true

    WAIT_SEC=0
    while kill -0 "$WF_PID" 2>/dev/null; do
      sleep 1
      WAIT_SEC=$((WAIT_SEC + 1))
      if [ "$WAIT_SEC" -ge 60 ]; then
        kill -9 "$WF_PID" 2>/dev/null || true
        break
      fi
    done

    wait $WF_PID
    INIT_RC=$?
    if [ $INIT_RC -ne 0 ]; then
      log "First-run init failed (exit code $INIT_RC). Leaving marker unset so init will retry on next start."
      exit $INIT_RC
    fi

    if grep -E 'Table "LAU_' "$WILDFLY_HOME/standalone/log/server.log" >/dev/null 2>&1; then
      log "Detected database schema errors during init. See $WILDFLY_HOME/standalone/log/server.log for details."
      exit 1
    fi

    log "Verifying schema by querying $DB_VERIFY_TABLE..."
    if ! schema_ready; then
      log "Schema verification query failed; leaving marker unset so init can retry."
      exit 1
    fi

    touch "$INIT_MARKER"
    if [ "$(id -u)" -eq 0 ]; then
      chown jboss:jboss "$INIT_MARKER" || true
    fi

    log "Initialization complete; marker created at $INIT_MARKER."
  fi
fi

log "Starting WildFly normally..."
if [ "$(id -u)" -eq 0 ]; then
  exec runuser -u jboss -- "$WILDFLY_HOME/bin/standalone.sh" $LAU_RUNTIME_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"
else
  exec "$WILDFLY_HOME/bin/standalone.sh" $LAU_RUNTIME_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"
fi