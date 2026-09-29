# Device commands

How a batch of device commands is split between paired gateways and the
platform, when a command is handed from one to the other, and what a caller
gets back for each command.

## Scope

Covers `lib/services/device_commands.dart`: `DeviceCommandsService`, the
gateway path `DeviceCommandPath` with its endpoint cache, and the platform
path `DeviceCommandCloud`. Not about what a command carries (the aspect fields
are in `docs/aspect-lists.md`), and not about how gateways are paired and
probed; that is `NetworkMixin`, which fills `Network.localGatewayHosts`.

## One batch per network

`DeviceCommandsService.runCommands` groups the commands by the network of
their device or group. A group whose network has a reachable gateway goes to
that gateway's device-command module, every other group goes to the platform.
All groups are sent at once.

The result holds one `DeviceCommandResponse` per command, at the command's
index, always. A command with neither device nor group, and a command its
batch did not answer, comes back as 502 `upstream reply null`.

## The gateway is tried first

`DeviceCommandPath` reads the module's endpoint from the Isar `endpoints`
collection and asks the gateway's core-manager only when none is cached. Any
failed gateway request drops the cached endpoint, so the next command looks
the module up again in case it has moved.

A command leaves the gateway path in three ways:

- **513 for a command**: the gateway does not serve that device. The command
  joins the platform batch.
- **The gateway took the batch but did not answer in time** (receive
  timeout): the gateway may still run the batch. A control (function id
  under `controllingFunctionPrefix`) is 502
  `gateway took the command but did not answer` and stays there, because
  running it twice is the harm. A read is idempotent and joins the platform
  batch like a 513.
- **Any other failure**: endpoint lookup, connect, send, or an error status.
  The whole group joins the platform batch. The app cannot tell a connection
  dropped after the body was sent, or an error status after a partial run,
  from a gateway that never took the batch, so those two can still run a
  command twice.

The commands collected that way go to the platform in one batch after the
gateway round.

## A platform answer is final

Commands are not idempotent, so a platform batch is never repeated. Its
answers are written as they come, 513 included. A platform request that fails
with a `DioException` answers 502 for each command; the message is
`ErrorReporter.offlineMessage` when the platform could not be reached, which
includes the availability interceptor's rejection in local mode, else
`platform answered <status>`.

Any other error from the platform path, such as a reply that is not a list,
propagates out of `runCommands`.

## Timeouts

The batch endpoint waits up to 10 s for the devices (`commandTimeoutSeconds`,
sent as `timeout=10s`), and both batch requests wait a second longer than
that (`batchReceiveTimeout`), so device-command's own timeout answer arrives
instead of a client-side 502 for a slow device. Every other request of the
two clients keeps its 5 s.

`prefer_event_value` is on by default, so device-command answers a reading
from the last event it saw when the service offers both events and requests.
The read-back after a control command passes `preferEventValue = false` to get
a fresh value from the device.

## What callers see

- `runCommandsSecurely` wraps `runCommands` for the widgets: an exception is
  reported through `ErrorReporter` and the call returns false; a 502 is an
  ordinary response, which the widgets toast as
  `Error running command: <message>`.
- `loadStates` (`lib/mixins/device_mixin.dart`) hands a 502 to the state's
  callback as null and reports only an exception.
- The Android widget (`lib/native_pipe.dart`) returns the responses as they
  are.

Both paths are driven through `FakeBackend` in
`test/device_commands_cloud_fallback_test.dart`; the gateway is served at
`gw.test`.
