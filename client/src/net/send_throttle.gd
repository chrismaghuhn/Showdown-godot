class_name SendThrottle
extends RefCounted
## Paces outgoing messages the way the server paces them (pokemon-showdown server/users.ts,
## User.chat): it runs one message per 600 ms, holds at most five more, and drops anything
## beyond with "Your message was not sent because you've been typing too quickly." The client
## keeps its own queue instead, sends a short burst right away and then one message per
## INTERVAL_MS - a little slower than the server, whose timers run late - so the server never
## has to drop one.
##
## A token bucket: CAPACITY messages can go out at once (below the server's 1 + 5), then a token
## comes back every INTERVAL_MS. back_off() empties it when the server dropped a message anyway.

const INTERVAL_MS := 650
const CAPACITY := 4
const BACK_OFF_MS := 2000

var _tokens := float(CAPACITY)
var _refilled_at := -1
var _paused_until := 0


## True if a message may go out now (and takes a token for it).
func take(now_ms: int) -> bool:
	_refill(now_ms)
	if now_ms < _paused_until or _tokens < 1.0:
		return false
	_tokens -= 1.0
	return true


## Milliseconds until take() can succeed again (0 = now).
func wait_ms(now_ms: int) -> int:
	_refill(now_ms)
	var until_token := 0 if _tokens >= 1.0 else ceili((1.0 - _tokens) * INTERVAL_MS)
	return maxi(until_token, _paused_until - now_ms)


## The server dropped a message: send nothing for a while and start from an empty bucket.
func back_off(now_ms: int, ms := BACK_OFF_MS) -> void:
	_tokens = 0.0
	_paused_until = now_ms + ms
	# Nothing refills during the pause, or the burst right after it would refill the server's
	# queue just as fast.
	_refilled_at = _paused_until


## True while a back-off is running.
func is_paused(now_ms: int) -> bool:
	return now_ms < _paused_until


## A new connection starts with a full bucket.
func reset() -> void:
	_tokens = float(CAPACITY)
	_refilled_at = -1
	_paused_until = 0


func _refill(now_ms: int) -> void:
	if _refilled_at < 0:
		_refilled_at = now_ms
		return
	# Never move backwards (a paused bucket, or a clock that went back) - no free tokens.
	if now_ms <= _refilled_at:
		return
	_tokens = minf(_tokens + float(now_ms - _refilled_at) / INTERVAL_MS, CAPACITY)
	_refilled_at = now_ms
