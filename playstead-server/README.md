# Playstead Server

This is the implementation root for the Elixir/Phoenix application.

It owns the canonical private repository, domain and application services, versioned HTTPS API, Phoenix LiveView web console, import/export, durable work, transfers, persistent-save revisions, backup evidence, and operational health.

The native-client protocol is API-first. LiveView may call the same application services inside Phoenix, but LiveView events, sockets, assigns, and HTML are not cross-platform protocol contracts.

The Phoenix application will be initialized here during Phase 1. Its Elixir application and module namespace is `playstead` / `Playstead`; the delivery namespace is `PlaysteadWeb`.
