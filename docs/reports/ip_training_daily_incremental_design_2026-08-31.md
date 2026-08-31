# Incremental design: `ip_training_daily`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed five-field training key is retained. No watermark covers the
current source-state composition, so this independent runner uses a read-only
snapshot, existing client/stage controls, exact row diff and no full rebuild.
