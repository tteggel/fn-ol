### A Dockerfile for a Fn Java function with an Oracle Linux base
#
# There are three images in this multi-stage Dockerfile:
#  1. A fdk-stage from where we copy the FDK runtime binaries.
#
#  2. A build-stage where we build your function code
#     ("Hello World") in this example.
#
#  3. A runtime-stage that builds an image that includes the output
#     of fdk-stage and build-stage. Resultant image be sent to your
#     Fn server with fn deploy and run with fn invoke.
#
# Images from stages 1 and 2 are thrown away after the build.
#
# NOTE: Keep the versions in the FROM clause of the fdk-stage and the
# build-stage in sync.

## 1. fdk-stage
#--------------

FROM fnproject/fn-java-fdk:jre11-1.0.80 as fdk-stage


## 2. build-image stage
#----------------------
# See https://github.com/fnproject/cli/blob/master/langs/java.go#L142

FROM fnproject/fn-java-fdk-build:jdk11-1.0.80 as build-stage

WORKDIR /function

# You can put proxies here if you need them for external access
ENV MAVEN_OPTS -Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort= -Dhttp.nonProxyHosts=127.0.0.1|localhost -Dmaven.repo.local=/usr/share/maven/ref/repository

ADD pom.xml pom.xml

RUN ["mvn", "package", "dependency:copy-dependencies", \
            "-DincludeScope=runtime", \
            "-DskipTests=true", \
            "-Dmdep.prependGroupId=true", \
            "-DoutputDirectory=target", \
            "--fail-never"]

ADD src /function/src

RUN ["mvn", "package"]


## 3. runtime-stage
#------------------

FROM oraclelinux:7-slim

# Must install the JRE in addition to any other deps you have here
RUN ["yum", "install", "-y", \
            "curl", \
            "jre-11"]

# Keep our image clean
RUN ["yum", "clean", "-y", "all"]
RUN ["/usr/bin/java", "-Xshare:dump"]

WORKDIR /function

# Copy in the FDK
COPY --from=fdk-stage /function/runtime runtime

# Copy output of build image (our function jars)
COPY --from=build-stage /function/target/*.jar app/

# We need to specify the ENTRYPOINT as we're not based off the FDK image.
#
# SerialGC is used here as it's likely that we'll be running many JVMs on the
# same host machine and it's also likely that the number of JVMs will outnumber
# the number of available processors.
#
# If using JRE < 11 then you will also want to set these to help JVM play nicely
# in a sandbox:
#
#    "-XX:+UnlockExperimentalVMOptions", \
#    "-XX:+UseCGroupMemoryLimitForHeap", \
#    "-XX:MaxRAMFraction=2", \
#    "-XX:-UsePerfData" \
# 
ENTRYPOINT [ "/usr/bin/java", \
              "-XX:-UsePerfData", \
              "-XX:+UseSerialGC", \
              "-Xshare:on", \
              "-Djava.library.path=/function/runtime/lib", \
              "-cp", "/function/app/*:/function/runtime/*", \
              "com.fnproject.fn.runtime.EntryPoint" ]

# This normally provided by CLI generated Dockerfile
CMD ["com.example.fn.HelloFunction::handleRequest"]