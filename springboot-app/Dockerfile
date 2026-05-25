# --------- STAGE 1: Build (native ARM for speed, output is platform-independent JAR) ---------
FROM maven:3.9.9-eclipse-temurin-17 AS builder

WORKDIR /app
COPY pom.xml .
# Cache dependencies as a separate layer
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests -q

# --------- STAGE 2: Runtime (linux/amd64 target) ---------
FROM --platform=linux/amd64 eclipse-temurin:17-jre-jammy

WORKDIR /app

# Download OTEL Java agent
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.4.0/opentelemetry-javaagent.jar otel-agent.jar

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-agent.observability.svc.cluster.local:4318"
ENV OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
ENV OTEL_SERVICE_NAME="springboot-app"
ENV OTEL_LOGS_EXPORTER="otlp"
ENV OTEL_METRICS_EXPORTER="none"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -javaagent:/app/otel-agent.jar -jar app.jar"]
