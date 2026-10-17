class_name ReconnectPolicy
extends RefCounted
## When to retry a lost or failed connection (design: "reconnecting in 4 s · Attempt 2 of 5").
##
## Attempt n waits BASE_DELAY * 2^(n-1) seconds, capped at MAX_DELAY: 2, 4, 8, 16, 30 s.
## A random ±JITTER spread keeps thousands of clients from reconnecting in the same second
## after a server restart. After MAX_ATTEMPTS failed attempts the client gives up and asks.

const MAX_ATTEMPTS := 5
const BASE_DELAY := 2.0
const MAX_DELAY := 30.0
const JITTER := 0.2


## Seconds to wait before `attempt` (1-based). `roll` in [0, 1] picks the jitter; 0.5 = none.
static func delay(attempt: int, roll := 0.5) -> float:
	var base := minf(BASE_DELAY * pow(2.0, maxi(attempt, 1) - 1), MAX_DELAY)
	return base * (1.0 + JITTER * (clampf(roll, 0.0, 1.0) * 2.0 - 1.0))


## True while another attempt after `failed_attempts` failures is allowed.
static func can_retry(failed_attempts: int) -> bool:
	return failed_attempts < MAX_ATTEMPTS
