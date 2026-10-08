# Android client (`gtk-llm-chat-android`) — implementation reference

Source repo: `/home/icarito/Proyectos/gtk-llm-chat-android` (TypeScript/React Native +
Kotlin). Scope: behavior a Godot 3 GDScript desktop client should match. Citations are
`file:line` in that repo unless a sibling repo is named explicitly.

## 1. Stable per-device resource suffix

The resource must carry a suffix that is **persisted**, not regenerated per launch. A
fresh random suffix each start makes the server treat every reconnect as a different
resource: it keeps the old session alive instead of replacing it, accumulating zombie
sessions (the source comment reports **317** seen in Prosody), each still receiving
carbons and firing push.

`src/xmpp/deviceResource.ts:3-39`:

```ts
const DEVICE_SUFFIX_KEY = '@gtk_llm_chat:device_resource_suffix';
// ...
const generated = Math.random().toString(36).slice(2, 10);   // 8 base36 chars
cached = generated;
await AsyncStorage.setItem(DEVICE_SUFFIX_KEY, generated);
```

Accessor `getDeviceResourceSuffix()` returns the cached/stored value; only generates when
storage is empty, and falls back to an ephemeral suffix (rather than failing to connect)
if storage throws. The resource is then composed at
`src/xmpp/XmppService.ts:1847`:

```ts
resource: `${config.resource || 'gtk-llm-chat-android'}-${deviceSuffix}`,
```

Desktop implication: `gtk-llm-chat-desktop-<persisted8>` — another resource value, so the
phone and desktop can both be online on the same account without fighting, while
same-device reconnects cleanly replace the previous session.

## 2. XEP-0308 correction folding

Namespace `urn:xmpp:message-correct:0`. The gateway streams an agent turn as repeated
`<replace>` edits of one seed stanza id. The client must **fold the whole chain into a
single row/bubble**, not create one message per edit — including when restoring from MAM.

Parse (`src/xmpp/XmppService.ts:278-285`); note the fallback scan because RN's `ltx` may
not resolve `xmlns` on `getChild`:

```ts
const replace = stanza.getChild('replace', MESSAGE_CORRECT_NS)
  ?? stanza.getChildren('replace').find((c) => c.attrs.xmlns === MESSAGE_CORRECT_NS);
return (replace?.attrs.id as string | undefined) || null;
```

Outbound builder exists but is not yet called by the app (`src/xmpp/outbound-render.ts:49-63`,
re-exported by `src/xmpp/xep-0308.ts`):

```xml
<message type='chat' to='...' id='nc-corr-...'>
  <body>FINAL TEXT</body>
  <replace xmlns='urn:xmpp:message-correct:0' id='SEED-ID'/>
</message>
```

Live path (`applyIncomingCorrection`, `src/xmpp/XmppService.ts:992-1040`): removes the
pending card by `replaceId`, rewrites the cached row, dismisses the notification, and
**replaces in place** the visible bubble (new body + **new timestamp = correction time**,
clears `quickResponses`/`commands`, sets `correctedAtMs = Date.now()` used for an
"in progress" affordance). A correction with **no matching bubble is ignored**, never
synthesized (prevents ghost rows from another conversation's carbons).

Persistence (`src/xmpp/XmppHistory.ts:493-508`):

```sql
UPDATE messages SET body=?, timestamp=?, quick_responses=NULL, commands=NULL,
       was_encrypted=MAX(was_encrypted,?)
 WHERE bare_jid=? AND stanza_id=?
```

MAM folding (`persistAndDedupe`, `src/xmpp/XmppService.ts:1429-1494`): every message id is
persisted as `stanza_id` (a correction target), and a correction is **never** stored as
its own row — it either updates the pending in-batch row or is folded when its target
page loads.

Edge cases pinned by tests (`__tests__/xmpp-history-corrections.test.ts:22-67`):
- Ordinary seed id `seed-1` is stored via `recordMessage(..., stanzaId='seed-1', ...)`.
- The archived correction `edit-1` with `replaceId='seed-1'` is folded via
  `applyCorrectionByStanzaId(jid,'seed-1','Respuesta final',<correction ts>, true)`.
- Result is one row: `{id:'seed-1', body:'Respuesta final', encryptionStatus:'encrypted'}`.
- `parseReplaceId` also reads a correction whose `<replace>` sits on the outer encrypted
  stanza (`__tests__/xmpp-actions.test.ts:17-26` → `'seed-1'`).

## 3. XEP-0050 ad-hoc commands + XEP-0439 quick responses

Namespaces (`src/xmpp/XmppService.ts:178-185`): `urn:xmpp:quick-response:0` (XEP-0439),
legacy `urn:xmpp:tmp:quick-response`, `http://jabber.org/protocol/commands`,
`...disco#items`.

Inline command items are the preferred action surface. Parsed only from
`<query xmlns='...disco#items' node='...commands'>` (`src/xmpp/XmppService.ts:287-309`):
attrs `jid`, `node`, `name` required; optional `style`
(`primary|secondary|success|danger`) and `expires-at-ms` (numeric string; `parseExpiresAtMs`
returns undefined if not finite, `:243-247`).

`parseActionMetadata` (`:311-320`) returns `{commands, quickResponses}` and **drops all
quick responses when any command item is present** — the command IQ wins, so the raw
`value` text is never shown as a button.

Quick responses (`parseQuickResponses`, `:249-270`) read BOTH namespaces and support two
shapes: `<response value label style expires-at-ms/>`, and
`<reference type='action'><body>…</body></reference>` (label = value = body text).

Selection IQ emitted by an inline button (`buildCommandExecuteStanza`,
`src/xmpp/outbound-render.ts:10-20`; asserted `__tests__/outbound-approval.test.ts:4-25`):

```xml
<iq type='set' to='operator@example.org/openclaw-operator' id='cmd-...'>
  <command xmlns='http://jabber.org/protocol/commands' node='cmd:approval-message:0' action='execute'/>
</iq>
```

Note the target is the **advertised full JID** from the item, not the bare JID. Full
execute→(form)→submit flow and form encoding live in `xep-0050.ts` server side
(`presentForm :200-227`, `executeAndComplete :248-276`, `commandCompleted :278-293`) and
client side `executeCommandWithFields` (`XmppService.ts:1132-1164`): first IQ `action='execute'`;
if `status='completed'` parse `<note>`/result form; otherwise the response carries
`sessionid`, and the client sends `action='complete'` with the submitted
`<x xmlns='jabber:x:data' type='submit'>`. Forms via `src/xmpp/xep-0004.ts`; booleans
normalized to `1`/`0` (`:7-9`).

`__tests__/xmpp-actions.test.ts` — each test's input → expected:
- `:17-26` outer `<replace>` on an encrypted stanza → `parseReplaceId === 'seed-1'`.
- `:28-45` body + standard `<response>`, `<reference type='action'>`, legacy `<response>`
  → exactly `[{Sí,yes},{no,no},{Abortar,abort}]`.
- `:47-71` disco items, first with `expires-at-ms='1784261952459'` → two commands; only
  the first carries `expiresAtMs`.
- `:73-101` command items + quick responses present → `quickResponses: []`, commands kept.
- `:103-131` gateway dual payload (`urn:xmpp:tmp` responses + `cmd:approval-message:*`) →
  quick responses dropped, both command nodes kept.
- `:133-150` legacy approval with opaque `value` → `actionsLookLikeApproval === true`,
  `approvalFallbackExpiry === timestamp + 30 min`.
- `:152-167` ordinary question (`Elige un color`) → not approval, no fallback expiry.
- `:169-174` `classifyApprovalCommandResult`: `Command submitted.`→`submitted`,
  `Command expired.`/`Approval already resolved.`→`expired`,
  `Failed to submit approval`→`rejected`.
- `:176-195` notification noise: ack `✅ Approval … submitted` → noise `true`; actionable
  `Approval required` + command → noise `false`.
- `:198-223` restored-action staleness: explicit future `expiresAtMs` keeps an old action;
  explicit past expiry kills a recent one; no `expiresAtMs` → falls back to 15 min;
  unparseable timestamp → keep (conservative).
- `:225-268` `findDenyAction`: `style==='danger'` wins even with opaque label; style beats
  a negative label on another action; never returns an approval-only group; matches
  `Denegar`/`Rechazar` without style; `Allow Once, no prompt` is **not** a deny.

## 4. Approval cards / inline buttons

Representation `XmppPendingAction` (`src/types/xmpp.ts:82-105`):
`{id, conversationJid, messageId, timestamp, detail, detailFull?, kind:'quick-response'|'command',
label, value?, jid?, node?, style?, expiresAtMs?, submitted?}`. `detail` is a short summary
(`extractApprovalSummary`, `outbound-render.ts:169-186`), `detailFull` the full markdown.

`expiresAtMs` = explicit `expires-at-ms` from the item/response, else an approval fallback
(`APPROVAL_FALLBACK_MAX_AGE_MS = 30 * 60 * 1000`, `XmppService.ts:642`; applied through
`approvalFallbackExpiry` `:695-704`). Approval detection is text/label/node heuristics
(`actionsLookLikeApproval :653-669`; `pendingGroupLooksLikeApproval :681-693`; per-action
`actionLooksLikeApproval :958-964`, tested in `__tests__/approval-ack-filter.test.ts`) — it
must not sweep away valid non-approval inline commands (`cmd:reset`, `cmd:context`,
`cmd:compact` → false).

Cards are pruned on expiry and their cache row metadata cleared so they cannot resurrect:
`isPendingActionExpired :635-637`, `pruneExpiredPendingActions :717-738` (calls
`XmppHistory.markResolvedByStanzaId`), `schedulePendingActionExpiry :740-756`. On restore,
`isRestoredActionStale` (`:1528-1535`, `PENDING_ACTION_MAX_AGE_MS = 15 * 60 * 1000`)
filters cards, but **does not delete the row metadata** when expired by local clock — a
gateway-side `expires-at-ms` may still be pending (`:1537-1570`). Prefer command items over
quick responses when both are present (`:867-870`).

Selection: `answerPendingAction` (`:2699-2740`) marks `submitted` optimistically; a
quick-response sends its `value` as a chat message, a command runs the selection IQ; on
failure it reverts `submitted` and rethrows. `expired` result clears the card locally.

## 5. XEP-0115 caps self-advertisement

Yes — the client announces its own caps in initial presence
(`src/xmpp/XmppService.ts:1987-1992`):

```xml
<presence><c xmlns='http://jabber.org/protocol/caps' hash='sha-1'
              node='https://github.com/icarito/gtk-llm-chat-android'
              ver='v4-telemetry-avatar-chatstates'/></presence>
```

- `CAPS_NODE` (`:209`) is the GitHub URL.
- `CAPS_FEATURES` (`:219-227`): `disco#info`, `<telemetry>+notify` (current + legacy
  node), `<avatar:metadata>+notify`, chatstates. `getActiveCapsFeatures` (`:229-235`) adds
  `eu.siacs.conversations.axolotl+notify` when OMEMO is enabled.
- The `ver` is an **opaque string, not a real SHA-1** (`:1885-1909`). No crypto dep is
  pulled in; Prosody does not validate the hash, and an unknown `ver` makes the server ask
  our full resource for disco#info anyway. Chosen as a hand-bumped label:
  `config.omemoEnabled ? 'v5-telemetry-avatar-chatstates-omemo' : 'v4-telemetry-avatar-chatstates'`
  (`:1909`).
- **Bump rule**: whenever `CAPS_FEATURES` changes, bump `ver`; a server that cached the old
  `node#ver` will not re-query and new features silently never advertise. Same for flipping
  OMEMO (v5 vs v4), to force contacts/cache invalidation.
- disco#info handler (`:2016-2037`) answers with identity
  `category='client' type='phone'` and echoes the requested `node`.
- `parseCaps` for a *contact* extracts only the node (`:119-123`), so agent detection uses
  the node/features, not `ver`.

## 6. Markdown → renderer: code fences + copy button

Renderer is the chat screen, not the transport. `app/xmpp-chat/[jid].tsx:57`:

```ts
const CODE_FENCE_RE = /```([^\n`]*)\n?([\s\S]*?)```/g;
```

`splitCodeFences` (`:83-104`) segments a body into `text` and `code` parts; language =
first whitespace token of the info string; code value strips one trailing `\n`. Render
(`:187-212`): each code part is a distinct block with a header showing
`part.language || 'code'`, a **copy button** calling
`Clipboard.setStringAsync(part.value)` (copies only that block), and horizontally
scrollable monospace `selectable` text. Text parts continue through
`splitMarkdownTables` (`src/xmpp/markdownTables.ts:40-75`) for `|` tables. Plain/fallback
renderings use `markdownToPlain` (`outbound-render.ts:155-167`), which unwraps fenced code
without backticks.

## 7. Stale delayed stanza guard + retention windows

`isStaleDelayedStanza` is **not defined in the Android repo** — it lives in
`openclaw-xmpp/src/protocol.ts:23,45-51` and is the authoritative guard a desktop client
should port:

```ts
const STALE_DELAY_MS = 5 * 60 * 1000;
export function isStaleDelayedStanza(stanza, now = Date.now()): boolean {
  const delay = stanza.getChild("delay", "urn:xmpp:delay");
  const stamp = delay?.attrs.stamp;
  if (typeof stamp !== "string") return false;
  const delayedAt = Date.parse(stamp);
  return Number.isFinite(delayedAt) && now - delayedAt > STALE_DELAY_MS;
}
```

A XEP-0203 `<delay>` older than 5 min must not become fresh agent input / a new turn.
Android's equivalents:
- Parse the delay stamp and prefer it over "now" (`extractDelayStamp`,
  `src/xmpp/XmppService.ts:152-158`; used for direct/carbon/MAM, `:2260-2263,2394,2414`).
- Notification-level replay guard: `REPLAY_MAX_AGE_MS = 10 * 60 * 1000` (`isReplay`,
  `src/xmpp/notifications.ts:189-197`) plus a 15 s post-connect grace
  (`CONNECT_GRACE_MS`, `:220-223`).
- Fresh-install catch-up window: `FRESH_INSTALL_CATCHUP_MS = 2 * 60 * 1000`
  (`src/xmpp/XmppHistory.ts:66-79`); everything the server dumps on a new DB is history and
  must not notify.
- Action retention: `PENDING_ACTION_MAX_AGE_MS = 15 * 60 * 1000` on restore
  (`XmppService.ts:1525-1535`).
- MAM retention/paging: `OVERLAP_MS = 7 days`, `MAM_PAGE_SIZE = 50`, `MAX_MAM_PAGES = 40`
  (`XmppService.ts:1328-1331`); `syncHistory` pages forward on the RSM `after` cursor and
  falls back to a bounded 7-day `start` only when the cache holds no archived id
  (`:2871-2914`). Server retention default = 1 week (plan §3.2); do not request more.
- MAM shadow dedupe window = 30 s (`cleanupMamShadowDuplicates`, `XmppHistory.ts:208-220`).

## GOTCHAS

1. Never regenerate the resource suffix per launch; persist it. Otherwise zombie sessions
   accumulate and each keeps receiving carbons/pushes (`deviceResource.ts:7-19`).
2. A XEP-0308 correction must fold into the target bubble/row and update its timestamp; do
   not synthesize a message when no target is loaded (`XmppService.ts:1013-1025`).
3. Prefer XEP-0050 command items over quick responses when both arrive; otherwise the raw
   `value` leaks into the UI (`XmppService.ts:315-318,867-870`).
4. `ver` in caps is opaque, not a SHA-1; bump it by hand whenever features or OMEMO toggles
   change, or new features silently fail to advertise (`XmppService.ts:1885-1909`).
5. Approval `expires-at-ms` absent → 30-min client fallback; restored cards with no expiry
   use a 15-min age cutoff, and an expired-by-local-clock row must not be deleted, only not
   rendered (`:642,1525-1570`).
6. `classifyApprovalCommandResult` distinguishes a `submitted` ack from an `expired`/
   `already resolved` result; do not treat an ack as resolution (`:706-715`).
7. `isXmppNotificationNoise` must not notify `Recibido · preparando…`, `Command submitted.`,
   `✅ Approval … submitted`, or tool/usage chatter (`notifications.ts:206-218`).
8. Delay/replay handling is layered: parse XEP-0203 (sort correctly), drop stale delayed
   stanzas >5 min (openclaw-xmpp), suppress notification replay >10 min, and suppress all
   notifications for 2 min after fresh install.
9. Code fences need a per-block copy action copying only that block's text, language label
   defaulting to `code` (`[jid].tsx:187-212`).
10. Dedupe by stanza id across live + carbon + MAM; a live row has no `mam_id` and must be
    matched/updated when the archive copy arrives, or it renders twice
    (`XmppHistory.ts:416-467`, `XmppService.ts:1420-1494`).
