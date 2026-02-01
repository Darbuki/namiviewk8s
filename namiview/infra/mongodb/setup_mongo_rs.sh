#!/bin/bash
set -e

# Defaults (match mongo_sts.yaml)
REPLICAS="${1:-3}"
NAMESPACE="${2:-namiview-infra}"
STS_NAME="${3:-mongo}"
SVC_NAME="${4:-mongo}"
RS_NAME="${5:-rs0}"
PORT="${6:-27017}"

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [[ "$REPLICAS" -lt 1 ]]; then
  echo "Usage: $0 [REPLICAS] [NAMESPACE] [STS_NAME] [SVC_NAME] [RS_NAME] [PORT]"
  echo "  REPLICAS  - number of replica set members (default: 3)"
  echo "  NAMESPACE - k8s namespace (default: namiview-infra)"
  echo "  STS_NAME  - StatefulSet name (default: mongo)"
  echo "  SVC_NAME  - headless service name (default: mongo)"
  echo "  RS_NAME   - replica set name (default: rs0)"
  echo "  PORT      - MongoDB port (default: 27017)"
  echo ""
  echo "Example: $0 5    # 5 members, other defaults"
  echo "Example: $0 3 namiview-infra mongo mongo rs0 27017"
  exit 1
fi

# Build members array: [{_id: 0, host: "mongo-0.mongo.namiview-infra.svc.cluster.local:27017"}, ...]
MEMBERS=""
for i in $(seq 0 $((REPLICAS - 1))); do
  HOST="${STS_NAME}-${i}.${SVC_NAME}.${NAMESPACE}.svc.cluster.local:${PORT}"
  if [[ -n "$MEMBERS" ]]; then
    MEMBERS="${MEMBERS}, "
  fi
  MEMBERS="${MEMBERS}{_id: ${i}, host: \"${HOST}\"}"
done

EVAL="rs.initiate({_id: \"${RS_NAME}\", members: [${MEMBERS}]})"
echo "Initializing replica set with ${REPLICAS} member(s)..."
echo "  namespace: ${NAMESPACE}, sts: ${STS_NAME}, rs: ${RS_NAME}"
echo "  eval: ${EVAL}"
echo ""

kubectl exec -it "${STS_NAME}-0" -n "${NAMESPACE}" -- mongosh --eval "${EVAL}"
