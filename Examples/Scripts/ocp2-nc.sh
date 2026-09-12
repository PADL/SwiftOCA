#!/bin/sh
#
# Drive an OCP.2 (AES70-4) device with nothing but nc(1).
#
# OCP.2 frames one JSON PDU per line, so a whole exchange is a line in and a
# line out and no client library is needed to poke at a device. Point it at the
# OCP.2 stream endpoint of Examples/OCADevice (port 65003) or at any other
# AES70-4 device:
#
#   sh Examples/Scripts/ocp2-nc.sh [host] [port]
#
# If jq(1) is installed, it checks and compacts each PDU before it is sent and
# pretty-prints the replies. Set JQ to use another jq, or JQ= to send and show
# the PDUs as they are.
#
# The WebSocket endpoint (port 65002 in the sample device, which serves OCP.1
# and OCP.2 there) is not reachable this way: it needs the HTTP upgrade, and the
# AES70-OCP.2 subprotocol to select OCP.2. Use websocat or a browser for that one.

set -e

HOST=${1:-localhost}
PORT=${2:-65003}

JQ=${JQ-jq}
if [ -n "$JQ" ] && ! command -v "$JQ" >/dev/null 2>&1; then
  JQ=
fi

# Half-closing the send side after each PDU makes the device answer and hang up
# at once, instead of holding the session open until nc gives up: -N is OpenBSD
# nc, -q 0 GNU. WAIT caps the wait when nc can do neither.
NC_EOF=
if nc -h 2>&1 | grep -q -- '-N'; then
  NC_EOF=-N
elif nc -h 2>&1 | grep -q -- '-q '; then
  NC_EOF='-q 0'
fi
WAIT=${WAIT:-2}

# The PDUs below are written across several lines for legibility, so fold each
# back into the single line OCP.2 frames.
compact() {
  if [ -n "$JQ" ]; then "$JQ" -c .; else tr -d '\n'; echo; fi
}

show() {
  if [ -n "$JQ" ]; then "$JQ" .; else cat; fi
}

# Send one PDU, print the reply. $NC_EOF is unquoted so that -q 0 splits into
# the two words nc wants; the device closes on end-of-input, so the reply ends
# the exchange and a CommandNR that answers nothing costs nothing either.
pdu() {
  printf '%s' "$1" | compact | nc $NC_EOF -w "$WAIT" "$HOST" "$PORT" | show
}

# ONo 1 is OcaDeviceManager, ONo 4 OcaSubscriptionManager and ONo 100 the root
# block (AES70-1 well-known object numbers); MethodID is [DefLevel, Index] and
# Parameters are keyed by the AES70-2A parameter names.

echo "== GetDeviceName (OcaDeviceManager 3.4)"
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":1,"TargetONo":1,"MethodID":[3,4]}]}'

echo
echo "== two commands in one PDU: GetDeviceName, GetModelDescription (3.6)"
pdu '{"ProtocolVersion":1,"Commands":[
        {"Handle":2,"TargetONo":1,"MethodID":[3,4]},
        {"Handle":3,"TargetONo":1,"MethodID":[3,6]}]}'

echo
echo "== GetActionObjects on the root block (OcaBlock 3.5)"
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":4,"TargetONo":100,"MethodID":[3,5]}]}'

echo
echo "== SetDeviceName (3.5), then read it back"
pdu '{"ProtocolVersion":1,"Commands":[
        {"Handle":5,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"Kitchen Amp"}}]}'
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":6,"TargetONo":1,"MethodID":[3,4]}]}'

echo
echo "== the same set as a CommandNRs: no response is sent"
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":7,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"OCA Test"}}]}'

echo
echo "== KeepAlive (HeartbeatTimeout is in milliseconds); the device echoes one back"
pdu '{"ProtocolVersion":1,"KeepAlive":{"HeartbeatTimeout":5000}}'

echo
echo "== a bad object number, to show the status names"
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":8,"TargetONo":65536,"MethodID":[3,4]}]}'

echo
echo "== subscribe to OcaDeviceManager's PropertyChanged event, then change a property"
# AddSubscription2 (OcaSubscriptionManager 3.8) has to be sent on the connection
# that is to receive the notifications, so this nc stays up while a second one
# makes the change. EventID [1,1] is OcaRoot's PropertyChanged; EV2 notifications
# come back over the same connection, so DestinationInformation is empty.
{
  printf '%s' '{"ProtocolVersion":1,"Commands":[
        {"Handle":9,"TargetONo":4,"MethodID":[3,8],"Parameters":{
          "Event":{"EmitterONo":1,"EventID":[1,1]},
          "NotificationDeliveryMode":1,"DestinationInformation":""}}]}' | compact
  sleep 4
} | nc $NC_EOF "$HOST" "$PORT" | show &
subscriber=$!

sleep 1
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":10,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"Studio B"}}]}'
wait $subscriber

echo
echo "== restoring the device name"
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":11,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"OCA Test"}}]}'
