# Changelog

## 1.5.7
- Fix luacheck warnings for CI packaging.

## 1.5.6
- Even slower smoother Kalman transitions.

## 1.5.5
- Soften Kalman transitions to avoid magnet feel between brackets.

## 1.5.4
- Remove `~` suffix from smoothed value.

## 1.5.3
- Crank Kalman responsiveness (gain 0.85, faster dt/adaptation).

## 1.5.2
- Increase Kalman gain/velocity adaptation for more responsive tracking.

## 1.5.1
- Smoothed value now integer (no decimals).

## 1.5.0
- Add Kalman-ish smoothing for bracket/bucket values (shows `N~`).

## 1.4.0
- Add nameplate-size interpolation: smooth estimates (`N~`) between 5-yd brackets using calibrated nameplate heights.

## 1.3.0
- Refactor: remove state machine and debug command; simplify to ~220 lines. Behavior unchanged.

## 1.2.1
- Show only the upper bound (e.g. `35`) instead of `30-35`.

## 1.2.0
- Show range interval (`10-15`) from LibRangeCheck instead of midpoint.
- Fall back to CheckInteractDistance buckets (`<=7`, `<=8`, `<=28`, `>28`).
- Infer melee from recent `PLAYER_SWING`.
- Cache last exact distance for 5s as `(stale)` when source stops answering.
- Add `/std debug` to dump all probe results.

## 1.0.1
- Add GameObject/Creature GUID distance via Closest*Position APIs.
- Show bracket midpoint as `~N` estimate.
- Self-target returns 0.0; minor refactor.

## 1.0.0
- Initial release.
