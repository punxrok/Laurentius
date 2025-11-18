#!/bin/bash
#
# Build script for Laurentius-zkp-plugin
# This script builds the plugin-zkp.war file
#

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Building Laurentius ZKP Plugin${NC}"
echo -e "${BLUE}============================================${NC}"

# Check if running from correct directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure we're using Java 8
if [ -d "/usr/lib/jvm/temurin-8-jdk-amd64" ]; then
    export JAVA_HOME=/usr/lib/jvm/temurin-8-jdk-amd64
    export PATH=$JAVA_HOME/bin:$PATH
    echo -e "${GREEN}Using Java 8 from: $JAVA_HOME${NC}"
elif command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
    echo -e "${BLUE}Using Java version: $JAVA_VERSION${NC}"
else
    echo -e "${RED}Java not found! Please install Java 8 or higher.${NC}"
    exit 1
fi

# Set Maven options to allow external schema access
export MAVEN_OPTS="-Djavax.xml.accessExternalSchema=all"

echo -e "${BLUE}Step 1: Building required dependencies...${NC}"
cd ../..
mvn clean install -DskipTests -pl Laurentius-libs,Laurentius-dao,Laurentius-msh -am

echo -e "${BLUE}Step 2: Building ZKP plugin...${NC}"
cd Laurentius-plugins/Laurentius-zkp-plugin
mvn clean package -DskipTests

# Check if WAR was created
if [ -f "target/plugin-zkp.war" ]; then
    WAR_SIZE=$(ls -lh target/plugin-zkp.war | awk '{print $5}')
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}WAR file created: target/plugin-zkp.war${NC}"
    echo -e "${GREEN}File size: $WAR_SIZE${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${RED}Build failed! WAR file not found.${NC}"
    exit 1
fi
