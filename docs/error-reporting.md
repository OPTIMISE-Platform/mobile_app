# Error reporting

Which failures the app tells the user about, which it records, and where each
lands. Three entry points, one rule each.

## Scope

Covers `lib/shared/error_reporter.dart`, the two global handlers installed in
`lib/main.dart`, and the diagnostics log model in
`lib/models/exception_log_element.dart`. Not about the MGW error codes in
`lib/services/mgw/error.dart`, which map a gateway's own responses.

## The three entry points

| Call | Console | Diagnostics log | Toast |
|---|---|---|---|
| `Toast.showToastNoContext` | no | no | yes |
| `ErrorReporter.log` | yes | yes | no |
| `ErrorReporter.report` | yes | yes | yes |

- **`Toast` alone** is for a message about something the user just did, where
  nothing failed that anyone would want to read later.
- **`ErrorReporter.log`** is for a failure nobody needs to be told about
  individually: what escapes a catch entirely, and what a widget already
  answers with its own message about the action.
- **`ErrorReporter.report`** is for a background failure the user should see.
  It collapses a burst: an identical message within five seconds is not shown
  again, and every failure whose cause is a missing connection is shown as one
  shared message instead of once per endpoint.

A widget that already shows its own message about the action calls both — its
`Toast` and `ErrorReporter.log`. That is deliberate rather than a missed
refactor: the string the user reads is about the action, the recorded one names
the failure.

## What the diagnostics log holds

`ExceptionLogElement` rows, kept seven days, rendered and shareable from the
debug dialog in settings.

The log holds **what was reported**. Until 0.0.390 it held every construction
of the five exception classes in `lib/exceptions`, because they inherited the
write from `ExceptionLogElement` and performed it in their constructors — so
raising one cost a database write, and the log filled with exceptions that are
ordinary control flow, such as the one every unauthenticated call raises.

That write now happens once, in `ErrorReporter.log`. The consequence to know:
a failure caught and handled without reporting leaves no trace. When adding a
catch block, decide which of the three entry points it needs.

Two deliberate omissions:

- The FCM registration endpoint carries the token in its path.
  `FcmTokenService` reports a masked address instead, because the debug dialog
  offers to share its contents.
- The sensor sparkline stays silent on a missing history. It loads per card, so
  a systemic failure would write one row per card, and a missing sparkline is
  not a failure the card cannot live with.

## The global handlers

`main.dart` installs `FlutterError.onError` and
`platformDispatcher.onError` before `runApp`. Both only record.

They do not show anything, for two reasons: a framework error can repeat every
frame, and a toast for it would bury the message belonging to whatever the user
was doing. `FlutterError.presentError` is still called first, so the console
output in debug is unchanged, and the platform handler returns `false`, so the
platform's own reporting still runs.

## Writing to the log must never throw

`ExceptionLogElement._persist` swallows everything, and that is load-bearing:
`ErrorReporter.log` is called from inside catch blocks all over the app, and a
throw there would replace the error being handled with an unrelated one.

The concrete cause it protects against is Isar's own rule — a synchronous write
transaction is refused while an asynchronous one is open in the same isolate,
and the chunked device cache holds one per chunk:

```
An async write transaction is already in progress in this isolate.
```

The refused write is retried asynchronously, at most 32 pending at a time,
because a retry itself holds an asynchronous transaction open and would
otherwise let an error burst queue one per exception. Beyond that the entry is
dropped and the drop is named on the console.
