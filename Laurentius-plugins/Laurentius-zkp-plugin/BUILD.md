# Building Laurentius ZKP Plugin

This document describes how to build the `plugin-zkp.war` file.

## Precompiled WAR File (No Build Required)

**If you don't want to install Java and Maven**, a precompiled WAR file is included in the repository:

```
dist/plugin-zkp.war
```

You can use this file directly without building from source.

## Building from Source

### Prerequisites

- **Java 8** or higher (Java 8 recommended)
- **Maven 3+**
- Internet connection (for downloading dependencies)

## Quick Build

The easiest way to build the plugin is to use the provided build script:

```bash
cd Laurentius-plugins/Laurentius-zkp-plugin
./build-plugin.sh
```

The script will:
1. Build all required dependencies (Laurentius-libs, Laurentius-dao, Laurentius-msh)
2. Build the ZKP plugin
3. Generate `target/plugin-zkp.war`

## Manual Build

If you prefer to build manually:

### Step 1: Build Dependencies

From the project root directory:

```bash
export JAVA_HOME=/usr/lib/jvm/temurin-8-jdk-amd64  # Adjust to your Java 8 installation
export PATH=$JAVA_HOME/bin:$PATH
export MAVEN_OPTS="-Djavax.xml.accessExternalSchema=all"

mvn clean install -DskipTests -pl Laurentius-libs,Laurentius-dao,Laurentius-msh -am
```

### Step 2: Build ZKP Plugin

```bash
cd Laurentius-plugins/Laurentius-zkp-plugin
mvn clean package -DskipTests
```

### Step 3: Get the WAR File

The compiled WAR file will be located at:
```
Laurentius-plugins/Laurentius-zkp-plugin/target/plugin-zkp.war
```

## Build Output

The build produces:
- **plugin-zkp.war**: The deployable WAR file (approximately 18MB)

## Troubleshooting

### Java Version Issues

If you encounter issues with JAXB or javax.activation classes:
- Make sure you're using Java 8
- Set the MAVEN_OPTS environment variable: `export MAVEN_OPTS="-Djavax.xml.accessExternalSchema=all"`

### Missing Dependencies

If the build fails with missing dependencies:
- Make sure you build the parent modules first (Laurentius-libs, Laurentius-dao, Laurentius-msh)
- Clean your local Maven repository if needed: `rm -rf ~/.m2/repository/si/vsrs/cif/sed`

### Network Issues

If you cannot access external repositories:
- Check your internet connection
- Check if you need to configure Maven proxy settings in `~/.m2/settings.xml`

## Notes

- The build skips tests by default to speed up the process
- All build artifacts are placed in the `target/` directory
- The `target/` directory is excluded from version control
