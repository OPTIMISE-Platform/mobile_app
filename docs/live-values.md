# Live values

How the readings on screen follow the device without a reload: MQTT events
from the paired gateway or from the platform, converted in the app.

## Scope

Covers `lib/live/` (`LiveValues`, `LiveConnection`, `ClientCertificates`,
`raw_output.dart`, `raw_value_source.dart`, `conversion/`), the views that
watch (detail page of a device, sensors page, PV visualization widget), the
broker login of a gateway pairing, and the live banner in `MyAppBar`.

Not about loading values on open or refresh, which goes through device
commands (`docs/device-commands.md`), and not about device groups: a group
page and group pins get no live values.

## Who watches

- `LiveValues.instance.watch(device)` returns a `LiveHandle`; `release()` ends
  it. The detail page of a device watches from `initState` to `dispose`.
- The sensors page keeps one watch per device of the shown tab
  (`_syncLive`). A load replaces the device objects, so it watches the new
  object before it releases the old one; the subscription and the connection
  survive the reload.
- The PV visualization widget calls `watchRaw(source, onValue)` for each of
  its `/db/v3/raw-value` request URLs (`RawValueSource.fromUrl`) and
  recomputes the flow with the one new value.
- Watches are counted per device. The first one subscribes, the last release
  unsubscribes, and a connection exists while one of its devices is watched.
  Every object that was watched for a device gets the values, not only the
  first.

## Route

The same choice as `DeviceCommandsService.runCommands`:

- The device's network has a paired gateway with an address
  (`device.network?.localGateways?.firstOrNull`): the gateway's broker on port
  1883 without TLS, topic `event/<local_id>/+`, with the broker login of that
  pairing if one is stored.
- Otherwise the platform: the broker in `LIVE_MQTT_URL` (`ssl://host:port`)
  with the account's client certificate, topic
  `event/<owner_id>/<local_id>/+`. The owner in the topic is the device's
  owner, so a device shared by another user works as long as the platform
  grants the read right. Without `LIVE_MQTT_URL` such devices get no live
  values.

The route of every watch is evaluated again when `AppState` notifies (a
gateway pairing becomes known after the first watch) and on resume.

The client id is `optimise-app-<installId>`, the install id a UUID kept in
the secure storage. A gateway connection appends the pairing id, because a
broker drops the older of two connections that share an id.

## Messages

- A platform event is a JSON object: one key per protocol segment name with
  the raw segment as a string, plus an optional `timestamp_rfc3339nano`, the
  time of the reading. Without it the receive time is used.
- A gateway event is the raw payload of the segment `data`; the gateway's
  cloud connector forwards the same payload as `{"data": <payload>}`.

For each state of the event's service that is not controlling and not
transitioning, `extractValue` reads the value at the state's path from the
segment of its content (`json` or `plain-text`) and converts it from the
characteristic of the content variable to the preferred characteristic of
the function (`Settings.getFunctionPreferredCharacteristicId`; none keeps
the raw value). Then the value is set, then `lastMessageTime`, then the
native pipe is told, and the device notifies once. Setting the value first
keeps a late-loaded time from replacing the live one.

A value that cannot be converted, or is not finite after conversion, leaves
the state as it is. Structured values (a map or list with a characteristic of
its own) and `xml` content are not updated live and keep their loaded value.

A gateway with `LDH_ID_PREFIX` set publishes the local id without the prefix,
which the app does not know; such a gateway gives no live values.

## Conversion

`LocalConverter` (`lib/live/conversion/`) converts in the app, so no
marshaller call is made per message. It holds the converter's fixed
characteristic edges and its input cleanup (every number becomes a double
before each step), adds the formula conversions of the concept
(`Concept.conversions`, loaded with the concepts), and takes the shortest
path by distance. The formula language is a subset of govaluate; the Go
behaviour reproduced on purpose and what is rejected are listed at the top of
`expression.dart`.

Protocols are loaded once per id through `ProtocolsService`; after a failed
load the id is not asked again for 30 s.

## Client certificate

One per account, in the secure storage:

- An EC P-256 key made on the phone. The CSR goes to `POST /ca/sign` with an
  expiration of `2160h`; the CA sets the common name to the user id.
- The hostname is `<device>.<clientId>`: manufacturer and model as the
  gateway pairing reports them, lowercased, every other character a `-`, at
  most 63 long, then the client id. The CA stores it as a dNSName, and it
  names phone and installation in the CA's list.
- From half of its validity on, a new certificate is signed for the same key;
  the old one is then revoked with `POST /ca/revoke`, reason `superseded`. A
  failed revoke is only logged. A certificate without this installation's
  hostname is replaced the same way at once, but only once per run, so a CA
  that leaves the hostname out is not asked on every connect.
- A renewal that fails keeps the old certificate in use while it is valid.
- A signing that ends after an account switch is discarded.
- A logout deletes the account's key and certificate without revoking
  (`ClientCertificates.forget`); an account switch deletes those of every
  other account (`forgetAllBut`).

## Connections

`LiveConnection` speaks MQTT 3.1.1 with QoS 0 and a keep-alive of 30 s. An
attempt is bounded at 12 s, because `mqtt_client` never completes `connect()`
when the TCP connection is refused. Retries wait 2 s, doubling up to 60 s,
and fetch fresh parameters (certificate, broker login) first. The
subscriptions are kept and sent again on every reconnect.

When the app is paused, every connection is closed and no retry runs. On
resume the account is checked, the routes are evaluated again, and every
connection reconnects and subscribes again.

## When a connection is missing

A connection that a view wants and that is not up counts as an outage after
`LiveValues.outageAfter` (10 s): not connected yet, dropped, login refused,
or no certificate. A drop that is over within that time counts as nothing.
`LiveValues.outages` lists the sources, the platform first; `AppState`
notifies on every change, and `MyAppBar` shows "No live values from …" below
the local mode or platform banner, naming every source in one line, a gateway
as the gateway list names it. A missing platform connection is left out while
the platform banner shows. While the app is paused the list is empty; on
resume the wait starts again.

The banner does not mark the platform unreachable, see
`docs/platform-outage.md`.

Not detected: a subscription the broker refuses (SUBACK `0x80`) and a broker
that is connected but delivers nothing.

## Gateway broker login

After a pairing the app connects to the gateway's broker without a login
(`probeMgwBroker`). If the broker refuses with "not authorized" or "bad user
name or password", a dialog asks for a login, which is stored under
`mgw-broker-credentials:<pairingId>` and deleted when the gateway is
unpaired. The gateway's status panel opens the same dialog for a pairing that
exists already.

Saving checks the login with a probe first. An accepted login closes the
dialog with a toast; a refused one stays in the dialog and is not stored. Any
other outcome (no answer, a refusal for another reason) stores the login and
says so in the dialog, with the broker's address and a "Check again" button.
A stored login makes the gateway's live connection, if it is down, reconnect
with it at once instead of after the retry delay
(`LiveValues.gatewayLoginChanged`).

## Tests

Widget tests open no real connection: `setUpGoldenEnvironment` sets
`LiveConnection.factory` to `OfflineLiveConnection`. The other hooks are
listed in `docs/testing.md`.
