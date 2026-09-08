FROM eclipse-temurin:8-jdk-alpine

WORKDIR /opt/smppsim

RUN mkdir -p /opt/smppsim/log

COPY smppsim.jar .
COPY conf/logging.properties ./conf/logging.properties
COPY conf/smppsim.props ./conf/smppsim.props
COPY www ./www
COPY lib ./lib


EXPOSE 2775 
EXPOSE 8088


ENTRYPOINT ["java", \
    "-Djava.net.preferIPv4Stack=true", \
    "-Djava.util.logging.config.file=conf/logging.properties", \
    "-jar", \
    "smppsim.jar", \
    "conf/smppsim.props"]