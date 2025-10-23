#!/bin/sh

# Set database dialect
DB_DIALECT='org.hibernate.dialect.H2Dialect'

# DB action: validate / update / create
DB_INI_ACTION='create'

# inet mask for access 0.0.0.0 - all access
LISTEN_MASK=0.0.0.0

quit () {
	echo "\nUsage:\n"
	echo "laurentius-demo.sh --init -d [DOMAIN] -l [LAU_HOME]\n"
	echo "  --init  initialize laurentius (database and demo data are loaded to database)"
	echo "  -d DOMAIN  -  if --init is set then domain must be given (ex.: company.org)"
	echo "  -l LAU_HOME  - path to application home folder (laurentius.home). If not given and --init is set then '[WILDFLY_HOME]/standalone/data/' is used."
	exit 1
}

# parse arguments
while [ "$#" -gt 0 ]
do
  key="$1"
  case $key in
    -w|--wildfly)
      WILDFLY_HOME="$2"
      shift
    ;;
    -l|--laurentius.home)
      LAU_HOME="$2"
      shift
    ;;
    --init)
      INIT="TRUE"
    ;;
    -d|--domain)
      LAU_DOMAIN="$2"
      shift
    ;;
    *)
      echo "unknown option: $key or bad list of arguments"
    ;;
  esac
  shift
done

DIRNAME=`dirname "$0"`
RESOLVED_WILDFLY_HOME=`cd "$DIRNAME/.." >/dev/null; pwd`
if [ "x$WILDFLY_HOME" = "x" ]; then
    WILDFLY_HOME=$RESOLVED_WILDFLY_HOME
else
 SANITIZED_WILDFLY_HOME=`cd "$WILDFLY_HOME"; pwd` 2>/dev/null || SANITIZED_WILDFLY_HOME="$WILDFLY_HOME"
 if [ "$RESOLVED_WILDFLY_HOME" != "$SANITIZED_WILDFLY_HOME" ]; then
   echo ""
   echo "   WARNING:  WILDFLY_HOME may be pointing to a different installation - unpredictable results may occur."
   echo ""
   echo "             WILDFLY_HOME: $WILDFLY_HOME"
   echo ""
   sleep 2s
 fi
fi

if [ "x$WILDFLY_HOME" = "x" ]; then
	echo "WILDFLY_HOME folder not defined! Check parameters!"
	quit;
fi

if [ ! -d "$WILDFLY_HOME" ]; then
	echo "WILDFLY_HOME folder not exists! Check parameters!"
	quit;
fi

if [ "x$LAU_HOME" = "x" ]; then
	LAU_HOME="$WILDFLY_HOME/standalone/data/laurentius-home";
fi

LAU_OPTS=" -c standalone-laurentius.xml -Dlaurentius.home=$LAU_HOME/"

if [ "$INIT" = "TRUE" ]; then
  # Non-interactive auto-accept via env var (suitable for containers/CI)
  if [ "${LAU_AUTO_ACCEPT:-false}" = "true" ]; then
    echo "LAU_AUTO_ACCEPT=true: proceeding with init non-interactively"
    answer=Y
  else
    # If we have a TTY, prompt; otherwise abort to avoid hanging in non-interactive start
    if [ -t 0 ]; then
      printf "Init will recreate database tables if exists. All data in tables will be lost. Do you want to continue? (Enter Y to continue) "
      read -r answer
    else
      echo "Non-interactive shell and LAU_AUTO_ACCEPT not set. Aborting init to avoid hanging."
      exit 1
    fi
  fi

  case "$answer" in
    [yY][eE][sS]|[yY])
      # proceed
    ;;
    *)
      echo "Init aborted by user"
      exit 1
    ;;
  esac

  if [ "x$LAU_DOMAIN" = "x" ]; then
    echo "Missing domain for initialization! Put domain after --init parameter. Ex.: laurentios-demo.sh --init -d test-company.org"
    quit;
  fi

  LAU_OPTS="$LAU_OPTS -Dlaurentius.hibernate.hbm2ddl.auto=$DB_INI_ACTION -Dlaurentius.hibernate.dialect=$DB_DIALECT -Dlaurentius.init=true -Dlaurentius.domain=$LAU_DOMAIN";
fi

echo "*********************************************************************************************************************************"
echo "* WILDFLY_HOME =  $WILDFLY_HOME"
echo "* LAU_HOME     =  $LAU_HOME"
echo "* INIT         =  $INIT"
echo "* LAU_OPTS     =  $LAU_OPTS"
echo "*********************************************************************************************************************************"

# Exec WildFly so Java becomes PID 1 (container stays running while server runs)
exec "$WILDFLY_HOME/bin/standalone.sh" $LAU_OPTS -b "$LISTEN_MASK" -bmanagement "$LISTEN_MASK"