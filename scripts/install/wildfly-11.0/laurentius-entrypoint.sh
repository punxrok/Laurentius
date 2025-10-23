#!/bin/sh
# laurentius-entrypoint.sh - first-run initializer + normal startup
set -e

DB_DIALECT=${DB_DIALECT:-org.hibernate.dialect.H2Dialect}
DB_INI_ACTION=${DB_INI_ACTION:-create}
LISTEN_MASK=${LISTEN_MASK:-0.0.0.0}
WILDFLY_HOME=${WILDFLY_HOME:-/opt/jboss/wildfly}
LAU_HOME=${LAU_HOME:-$WILDFLY_HOME/standalone/data/laurentius-home}
LAU_AUTO_INIT=${LAU_AUTO_INIT:-true}
INIT_MARKER="$LAU_HOME/.initialized"

# Ensure directories exist and have permissive perms for jboss
mkdir -p "$LAU_HOME"
mkdir -p "$WILDFLY_HOME/standalone/log"
chown -R jboss:jboss "$LAU_HOME" "$WILDFLY_HOME/standalone/log" || true
chmod -R a+rwX "$LAU_HOME" "$WILDFLY_HOME/standalone/log" || true

LAU_OPTS=" -c standalone-laurentius.xml -Dlaurentius.home=$LAU_HOME/"

if [ ! -f "$INIT_MARKER" ] && [ "x$LAU_AUTO_INIT" != "xfalse" ]; then
  if [ -z "$LAU_DOMAIN" ]; then
    echo "LAU_DOMAIN not set; skipping auto-init"
  else
    echo "Performing first-run initialization..."
    INIT_OPTS="$LAU_OPTS -Dlaurentius.hibernate.hbm2ddl.auto=$DB_INI_ACTION -Dlaurentius.hibernate.dialect=$DB_DIALECT -Dlaurentius.init=true -Dlaurentius.domain=$LAU_DOMAIN"
    "$WILDFLY_HOME/bin/standalone.sh" $INIT_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK" >/dev/null 2>&1 &
    WF_PID=$!
    WAIT_SEC=0
    MAX_WAIT=180
    echo "Waiting for server to start for initialization..."
    while ! grep -q "WFLYSRV0025: WildFly .* started" "$WILDFLY_HOME/standalone/log/server.log" 2>/dev/null; do
      sleep 1
      WAIT_SEC=$((WAIT_SEC+1))
      if [ "$WAIT_SEC" -ge "$MAX_WAIT" ]; then
        echo "Timeout waiting for server to start. Aborting init."
        kill "$WF_PID" || true
        exit 1
      fi
    done
    sleep 5
    echo "Shutting down initialization server..."
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --controller=localhost:9990 --command=":shutdown" >/dev/null 2>&1 || true
    WAIT_SEC=0
    while kill -0 "$WF_PID" 2>/dev/null; do
      sleep 1
      WAIT_SEC=$((WAIT_SEC+1))
      if [ "$WAIT_SEC" -ge 60 ]; then
        kill -9 "$WF_PID" 2>/dev/null || true
        break
      fi
    done
    touch "$INIT_MARKER"
    chown jboss:jboss "$INIT_MARKER" || true
    echo "Initialization complete; marker created at $INIT_MARKER."
  fi
fi

echo "Starting WildFly normally..."
exec "$WILDFLY_HOME/bin/standalone.sh" $LAU_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"