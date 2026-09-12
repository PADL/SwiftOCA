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
# the PDUs as they are; the role tree is skipped without it.
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

# Send one PDU, return the reply. $NC_EOF is unquoted so that -q 0 splits into
# the two words nc wants; the device closes on end-of-input, so the reply ends
# the exchange and a CommandNR that answers nothing costs nothing either.
send() {
  printf '%s' "$1" | compact | nc $NC_EOF -w "$WAIT" "$HOST" "$PORT"
}

# The same, pretty-printed, for the exchanges that are not fed to another PDU.
pdu() {
  send "$1" | show
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
echo "== GetActionObjectsRecursive (3.6): the whole hierarchy in one PDU"
# The answer is flat, each member naming its parent in ContainerObjectNumber, so
# one round trip covers a tree of any depth. 3.6 is optional: a device that does
# not implement it has to be walked a block at a time with the 3.5 above.
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":5,"TargetONo":100,"MethodID":[3,6]}]}'
echo
echo "== the same hierarchy as a tree, with each object's role"
if [ -z "$JQ" ]; then
  echo "(needs jq)"
else
  members=$(send '{"ProtocolVersion":1,"Commands":[
        {"Handle":6,"TargetONo":100,"MethodID":[3,6]}]}')
  # Roles are OcaRoot 1.5, and OCP.2 batches, so one more PDU fetches them all.
  # A response carries its Handle and not its ONo, so number the commands by
  # their index into the ONo list and join the two answers on that.
  roles=$(printf '%s' "$members" | "$JQ" -c '
    [100] + [.Responses[0].Parameters.Objects[]?.MemberObjectIdentification.ONo] |
    {ProtocolVersion: 1,
     Commands: [to_entries[] | {Handle: .key, TargetONo: .value, MethodID: [1, 5]}]}')
  # The hierarchy of a real device runs past the 128 KiB a single argument can
  # hold, so the three documents are slurped from stdin rather than --argjson'd.
  { printf '%s\n' "$members" "$roles"; send "$roles"; } | "$JQ" -s '
    .[0] as $members | .[1] as $query | .[2] as $replies |
    ($query.Commands | map({key: (.Handle | tostring), value: .TargetONo}) | from_entries) as $ono |
    ($replies.Responses | map({key: ($ono[.Handle | tostring] | tostring),
                               value: (.Parameters.Role // "?")}) | from_entries) as $role |
    ($members.Responses[0].Parameters.Objects // []) as $objects |
    def members($container):
      [$objects[] | select(.ContainerObjectNumber == $container)] |
      map(.MemberObjectIdentification |
          # a nonstandard class embeds its authority as [65535, "<org ID>"]
          {ONo, Role: $role[.ONo | tostring],
           ClassID: (.ClassIdentification.ClassID |
                     map(if type == "array" then join(":") else tostring end) | join(".")),
           Members: members(.ONo)});
    {ONo: 100, Role: $role["100"], Members: members(100)}'
fi

echo
echo "== SetDeviceName (3.5), then read it back"
pdu '{"ProtocolVersion":1,"Commands":[
        {"Handle":7,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"Kitchen Amp"}}]}'
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":8,"TargetONo":1,"MethodID":[3,4]}]}'

echo
echo "== the same set as a CommandNRs: no response is sent"
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":9,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"OCA Test"}}]}'

echo
echo "== KeepAlive (HeartbeatTimeout is in milliseconds); the device echoes one back"
pdu '{"ProtocolVersion":1,"KeepAlive":{"HeartbeatTimeout":5000}}'

echo
echo "== a bad object number, to show the status names"
pdu '{"ProtocolVersion":1,"Commands":[{"Handle":10,"TargetONo":65536,"MethodID":[3,4]}]}'

echo
echo "== subscribe to OcaDeviceManager's PropertyChanged event, then change a property"
# AddSubscription2 (OcaSubscriptionManager 3.8) has to be sent on the connection
# that is to receive the notifications, so this nc stays up while a second one
# makes the change. EventID [1,1] is OcaRoot's PropertyChanged; EV2 notifications
# come back over the same connection, so DestinationInformation is empty.
{
  printf '%s' '{"ProtocolVersion":1,"Commands":[
        {"Handle":11,"TargetONo":4,"MethodID":[3,8],"Parameters":{
          "Event":{"EmitterONo":1,"EventID":[1,1]},
          "NotificationDeliveryMode":1,"DestinationInformation":""}}]}' | compact
  sleep 4
} | nc $NC_EOF "$HOST" "$PORT" | show &
subscriber=$!

sleep 1
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":12,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"Studio B"}}]}'
wait $subscriber

echo
echo "== restoring the device name"
pdu '{"ProtocolVersion":1,"CommandNRs":[
        {"Handle":13,"TargetONo":1,"MethodID":[3,5],"Parameters":{"Name":"OCA Test"}}]}'
