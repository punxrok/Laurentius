#!/bin/sh

# Set database dialect
DB_DIALECT='org.hibernate.dialect.H2Dialect'
DB_INI_ACTION='create'
LISTEN_MASK=0.0.0.0

quit () {
  echo ""
  echo "Usage:"
  echo "  laurentius-demo.sh --init -d [DOMAIN] -l [LAU_HOME]"
  echo ""
  exit 1
}

# Parse args
while [ "$#" -gt 0 ]
do
  key="$1"
  case $key in
    -w|--wildfly)
      WILDFLY_HOME="$2"; shift
    ;;
    -l|--laurentius.home)
      LAU_HOME="$2"; shift
    ;;
    --init)
      INIT="TRUE"
    ;;
    -d|--domain)
      LAU_DOMAIN="$2"; shift
    ;;
    *)
      echo "unknown option: $key"
    ;;
  esac
  shift
done

DIRNAME=`dirname "$0"`
RESOLVED_WILDFLY_HOME=`cd "$DIRNAME/.." >/dev/null; pwd`
if [ "x$WILDFLY_HOME" = "x" ]; then
  WILDFLY_HOME=$RESOLVED_WILDFLY_HOME
fi

if [ "x$LAU_HOME" = "x" ]; then
  LAU_HOME="$WILDFLY_HOME/standalone/data/laurentius-home"
fi

LAU_OPTS=" -c standalone-laurentius.xml -Dlaurentius.home=$LAU_HOME/"

# Marker file: indicates initialization already completed
INIT_MARKER="$LAU_HOME/.initialized"

# Allow forcing init via env var LAU_INIT=true
if [ "${LAU_INIT:-false}" = "true" ]; then
  INIT="TRUE"
fi

if [ "$INIT" = "TRUE" ]; then
  # If marker exists, skip re-initialization
  if [ -f "$INIT_MARKER" ]; then
    echo "Initialization marker found at $INIT_MARKER — skipping database init."
  else
    # Non-interactive auto-accept via env var
    if [ "${LAU_AUTO_ACCEPT:-false}" = "true" ]; then
      echo "LAU_AUTO_ACCEPT=true: proceeding with init non-interactively"
      answer=Y
    else
      if [ -t 0 ]; then
        printf "Init will recreate database tables if exists. All data in tables will be lost. Do you want to continue? (Enter Y to continue) "
        read -r answer
      else
        echo "Non-interactive shell and LAU_AUTO_ACCEPT not set. Aborting init to avoid hanging."
        exit 1
      fi
    fi

    case "$answer" in
      [yY][eE][sS]|[yY]) ;;
      *)
        echo "Init aborted by user"; exit 1;;
    esac

    if [ "x$LAU_DOMAIN" = "x" ]; then
      echo "Missing domain for initialization! Use --init -d example.org" ; quit;
    fi

    LAU_OPTS="$LAU_OPTS -Dlaurentius.hibernate.hbm2ddl.auto=$DB_INI_ACTION -Dlaurentius.hibernate.dialect=$DB_DIALECT -Dlaurentius.init=true -Dlaurentius.domain=$LAU_DOMAIN"
    echo "Running initialization..."
    # Run WildFly with init options (exec will replace shell)
    exec "$WILDFLY_HOME/bin/standalone.sh" $LAU_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"
    # After exec returns (shouldn't), but if init routine exits, create marker — handled by user or by separate process.
  fi
fi

echo "*********************************************************************"
echo "* WILDFLY_HOME =  $WILDFLY_HOME"
echo "* LAU_HOME     =  $LAU_HOME"
echo "* INIT         =  $INIT"
echo "* LAU_OPTS     =  $LAU_OPTS"
echo "*********************************************************************"

# Normal startup (no DB recreate). Exec WildFly so it remains PID 1.
exec "$WILDFLY_HOME/bin/standalone.sh" $LAU_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"