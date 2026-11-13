# Callback Race Kit

> **Status:** Early-stage reference implementation; APIs may change.

A small Swift package for the awkward moment when a callback API meets task cancellation.

Legacy callbacks can fire synchronously, fire twice, arrive after cancellation, or race with the cancellation token being returned. Callback Race Kit gives one async call a single winner: the first result or cancellation resumes the awaiting task, and later completions are ignored.

## ✨ Example

~~~swift
let image = try await CallbackBridge.run { finish in
    let request = legacyImageLoader.load(url) { result in
        finish(result)
    }

    return CancellationToken {
        request.cancel()
    }
}
~~~

If the callback API cannot be cancelled, return nil. The async caller still receives CancellationError, and any later callback is safely ignored.

## What it handles

- Completion before the registration function returns.
- Cancellation before registration is skipped; cancellation racing after registration begins is forwarded as soon as its token is returned.
- Cancellation after a cancellation token is attached.
- Duplicate and late callback delivery.
- Thread-safe completion from callback queues.

## Install

Add the package URL to a Swift Package Manager dependency:

~~~swift
.package(url: "https://github.com/j-khn/callback-race-kit.git", branch: "main")
~~~

Import CallbackRaceKit in the target that wraps the legacy API.

## Scope

This is a focused one-shot bridge built on Swift continuations and cancellation handlers. It does not make an uncooperative API cancellable, and it does not replace structured concurrency for new APIs. The callback's first result wins if it races with cancellation.

## Compatibility

Swift 6.0+, iOS 16+, and macOS 13+.

## License

MIT.
