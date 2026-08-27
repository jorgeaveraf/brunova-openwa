# Incident response

## Account or session compromise

Restrict network access immediately, stop the OpenWA container without deleting its volume, revoke
the linked device from WhatsApp on the phone, rotate API and proxy credentials, preserve encrypted
forensic copies, and inspect audit/access logs. Do not reconnect the old profile until the cause is
known. Treat any exposed QR or copied session directory as credential compromise.

## Readiness failure or restart loop

Capture `docker inspect brunova-openwa`, recent redacted logs, `docker stats --no-stream`, host
RAM/swap/disk, and volume usage. Check OOM kills, PID limit, SQLite errors, read-only filesystem
errors, and Chromium launch/crash messages. Stop repeated restarts if they threaten the host, then
roll back the image. Restore data only if migration evidence requires it.

## Disconnected session or repeated QR

Do not automatically scan or distribute a QR. Confirm WhatsApp service/account state and whether a
browser upgrade invalidated the profile. Preserve the prior profile and backup before retrying.
Escalate restrictions or ban indicators; do not compensate with reconnect bursts or additional
sessions.

## Webhook failures or loops

Disable the affected webhook/automation rule, retain failure metadata without message bodies, and
verify idempotency keys/deduplication at the receiver. SSRF protection must remain enabled. Reduce
concurrency rather than retrying in bursts; outbound send pacing is a final guard, not loop logic.

## Host pressure

At sustained RAM above 80–85%, growing swap, disk above 75–80%, or repeated OOM/restarts, stop the
unlinked OpenWA container first and reassess capacity. Do not prune volumes. If production is linked,
prefer a controlled stop and maintenance window over allowing Chromium crash loops.

After containment, document timeline, release/digest, last known healthy state, affected session,
credential rotations, recovery source, restore/smoke results, and preventive action. Do not include
secrets, QR images, message bodies, or raw session data in the incident record.
