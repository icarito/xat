# gtk-llm-chat — XMPP wire-format & algorithm reference

Source repo: `/home/icarito/Proyectos/gtk-llm-chat` (Python 3, PyGObject/GTK4).
Transport: `nbxmpp` `nbxmpp.client.Client` over the GLib main loop
(`xmpp_client.py:27`). Two layers: `XmppSession` = one connection per account,
`XmppConversation` = `ChatBackend` per bare JID (`xmpp_client.py:173,1816`).
Citations are `file:line`. XML under `nbxmpp/modules/*.py` is the literal
wire form nbxmpp emits/parses for the calls this client makes.

## 1. Connection / session lifecycle

- Library: **nbxmpp** (unpinned in `requirements.txt`; venv has 7.x).
- Resource: fixed base `RESOURCE = 'gtk-llm-chat-desktop'` plus a **stable
  per-install suffix** persisted in `<userdir>/xmpp_resource_suffix` (8 hex
  chars from `uuid4`, written once): `self._resource = f"{resource}-{suffix}"`
  (`xmpp_client.py:44,48-74,227`). Stable resource lets a reconnect *replace*
  the prior session instead of leaving zombie sessions (`:51-58`).
- Connect (`connect_to_server`, `:286-359`): guards non-idle states, then
  **reuses the existing `Client` object** if present so nbxmpp can request SM
  resume; only creates `NbxmppClient` on first connect. Registers handlers:
  `message`, `presence`, `a` (stream-mgmt, priority 60) (`:318-327`).
  EntityCaps advertises `telemetry+notify`, `avatar:metadata+notify`, optional
  OMEMO namespaces (`:336-352`).
- `_on_connected` (`:500-506`) → `request_roster()` (RFC 6121 order), then in
  `_on_roster` sends initial `<presence/>` then enables carbons, then sets
  `STATE_CONNECTED`.
- Reconnect/backoff (`:540-562`): `delay = min(60, 2 ** min(attempt,5))`; one
  timer at a time (`_cancel_reconnect_timer`), `auto_reconnect` can be off.
  `_should_reconnect` suppresses retry on auth markers
  `('not-authorized','not authorized','sasl','authentication')` (`:540-545`).
- **Auth failure detection**: a wrong password does NOT fire
  `connection-failed`; it surfaces via `disconnected` →
  `error, text, _ = self._client.get_error()` then `session-error` emit
  (`:508-529`). `_on_connection_failed` same pattern (`:531-538`).
- XEP-0198 SM: entirely inside nbxmpp (`smacks.py` sends
  `<enable xmlns='urn:xmpp:sm:3' resume='true'/>`; `<r/>`/`<a h='N'/>`;
  `<resume previd=... h=.../>`). Client reuses the Client object to allow
  resume; on a **voluntary** disconnect it sets `self._client = None` so the
  next connect is fresh (clean `</stream>` invalidates server smacks)
  (`:511-518`). Outgoing delivery ack (`_on_sm_ack`, `:1524-1533`) reads
  `<a h='N'/>` and marks pending stanzas whose recorded
  `_smacks._out_h` sequence `<= handled`.
- XEP-0199 ping: not driven by this client; nbxmpp pings the domain every
  **180 s** with a 10 s timeout and `disconnect(immediate=True)` on timeout
  (`nbxmpp/client.py:822,1106-1128`).
- Lifecycle UI phases (`xmpp_lifecycle.py:64-82`): `connecting/syncing-roster/
  connected/reconnecting/disconnected` → `CONNECTING/SYNCING_ROSTER/ONLINE/
  RETRYING/RETRYING`; a prior ERROR is preserved over a following `disconnected`
  (`:68-72`), and user-initiated offline pins `OFFLINE_BY_USER` (`:52-67`).

## 2. Roster + presence aggregation

- `roster_items[bare]` = `{name, subscription, presence, status, is_agent,
  agent_full_jid}`; reset on every roster (re)load, and
  `self._online_resources = {}` is cleared at the same time to avoid phantom
  online resources on reconnect (`xmpp_client.py:584-596`).
- Exact pattern (`_on_presence`, `:803-864`):
  ```python
  resources = self._online_resources.setdefault(bare, set())
  if ptype.value == 'unavailable': resources.discard(resource)
  else:                            resources.add(resource)   # available
  is_online = bool(resources)          # bare JID online iff >=1 resource
  state = self._presence_state(is_online, show_value, status)
  ```
  `resource = properties.jid.resource`; presence of JIDs not in
  `roster_items` is ignored (`:831-834`). `is_agent`/`agent_full_jid` set when
  `entity_caps.node == AGENT_CAPS_NODE`
  (`'https://github.com/openclaw/openclaw'`, `:77,841-845`).
- Status aggregation (`:866-876`): `dnd`/`busy` show or
  `"availability":"busy"` in status → BUSY; `away`/`xa`, or
  `"availability":"away"`/`"activity":"paused"` in status → AWAY; else ONLINE.
- Priority is **not** tracked/combined; "online" is set membership only, and
  the agent's status is opaque text (telemetry rides PEP, not `<status>`).
  Emitted only on state change (`presence-changed`) or status/caps change
  (`contact-status-changed`) (`:856-864`).
- Inbound `<presence type='subscribe'>` → `subscription-request`; accept sends
  `subscribed` + reciprocal `subscribe` (`:821-826,1771-1778`).

## 3. Message handling (XEPs 0085 / 0184 / 0280 / 0203)

Single entry `_on_message` (`:981-1272`). Order: OMEMO unwrap → error stanza →
self-carbon → MAM → chatstate/receipt path → normal.

- **XEP-0085 chat states**: parse via nbxmpp `properties.has_chatstate` /
  `properties.chatstate` → `conversation.notify_chatstate(str(...))`
  (`:1228-1229`), then `emit('typing', chatstate.endswith('COMPOSING'))`
  (`:2040-2041`). Sent as a child of the message; every outgoing text message
  carries `<active xmlns='http://jabber.org/protocol/chatstates'/>` plus an
  optional standalone `<composing/>` via `send_chatstate` (`:1451-1452,
  1757-1768`).
- **XEP-0184 receipts**: **not implemented** (no `<request/>`/`<received/>`
  anywhere). Delivery state comes from SM acks (`:1524-1533`) and IQ errors
  (`:1158-1163`).
- **XEP-0280 carbons**: enabled once after roster with a *direct child* of the
  iq (not wrapped in `<query>`):
  ```python
  enable_carbons = Iq(typ='set')
  enable_carbons.addChild('enable', namespace=Namespace.CARBONS)
  ```
  (`:606-610`). Incoming: `properties.is_carbon_message and
  properties.carbon.is_sent` (`:1164-1165`). A sent-carbon is *not* a new
  bubble; it (a) resolves a pending quick-response by body
  (`notify_own_carbon`, `:2022-2038`) and (b) is persisted unless a recent
  identical outgoing row exists (`has_recent_outgoing`, 120 s window,
  `:2016-2019`; `xmpp_history.py:290-315`).
- **XEP-0203 delay**: no explicit `<delay/>` parsing. nbxmpp surfaces the MAM
  forwarded delay as epoch float `properties.mam.timestamp`, normalised to
  ISO-8601 UTC (`datetime.fromtimestamp(..., timezone.utc).isoformat()`,
  `:1207-1209`); live messages use `datetime.now(timezone.utc)`. There is **no
  date-separator computation** in this app (grep empty): rendering only maps
  ISO/epoch → local via `astimezone()` + `strftime('%H:%M')`
  (`chat_window.py:3328-3353`).
- Normal inbound (`:1233-1272`): `body = _body_with_oob(stanza, properties.body)`
  (synthesises a body from XEP-0066 OOB link if empty, `:1306-1339`); parse
  quick-responses + inline commands; `stanza_id = _stanza.getAttr('id')`;
  `replace_id = _parse_replace_id(...)`. Conversation `deliver(...)`, then
  `chat-message-delivered`. Notifications: an edit never notifies unless it
  targets the latest original (`_should_update_notification`, `:1279-1283`).

## 4. XEP-0308 corrections — exact fold algorithm

- Namespace `MESSAGE_CORRECT_NS = 'urn:xmpp:message-correct:0'` (`:162`).
  Parse only: `stanza.getTags('replace', ns)[0].getAttr('id')` (`:1409-1413`).
  This client **receives** corrections; it never emits `<replace>`.
- **Correlation/dedupe key = the original message's own stanza id**, carried as
  `request_id` (the `<replace id=...>` value). Live path:
  `correction = (replace_id, stanza_id)` (`:1241`). `deliver` accepts a
  correction when `_is_known_correction_target(replace_id)` (recent ids,
  bounded 100, `_known_incoming_ids`; or a pending quick-response request,
  bounded 50, `_pending_request_ids`) (`:1875-1904,1940-1952`).
- Fold in memory/SQL: `_deliver_correction` → `history.update_by_request_id`
  (`UPDATE ... SET body=? WHERE bare_jid=? AND request_id=?`, also clears
  quick_responses/commands) and emits `response-correction` (`:1983-1992`;
  `xmpp_history.py:335-346`). Successive edits reference the *original* id, so
  exactly one row is rewritten.
- Unknown target (opened mid-turn): anchored under the original id —
  `record_message(..., request_id=replace_id)` + `_track_incoming_id` +
  `response-message`, so later edits collapse onto it (`:1888-1904`).
- **Restore from MAM** (`_collapse_mam_corrections`, `:2273-2318`): page items
  are tuples `(body,direction,ts,mam_id,quick,commands,stanza_id,replace_id)`.
  ```python
  position_by_request = {}
  for item in page:
      if replace_id and direction=='in':
          pos = position_by_request.get(replace_id)
          if pos is not None:                 # 1. same page: rewrite body+actions
              output[pos] = (body, prev[1], prev[2], prev[3], quick, commands, prev[6])
              continue
          if history.update_by_request_id(bare, replace_id, body):  # 2. known row
              continue
          request_id = replace_id             # 3. anchor unknown as new
      if request_id and direction=='in':
          position_by_request[request_id] = len(output)
      output.append((body, direction, ts, mam_id, quick, commands, request_id))
  ```
  Timestamp/original direction are kept from the anchor so a streaming turn
  renders as one bubble at the seed's time.
- SQLite row identity / last-resort dedupe: **`UNIQUE(bare_jid, mam_id)`**,
  inserts use `INSERT OR IGNORE` (`xmpp_history.py:26,140-151`). MAM reattach
  matches a live row by `(bare_jid, request_id, direction='in', mam_id IS NULL)`
  (`attach_mam_to_request_id`, `:462-486`) before falling back to
  body+direction+nearest-timestamp within 120 s (`attach_mam_to_recent_message`,
  `:519-571`).

## 5. XEP-0313 MAM

- **No preflight/disco#info negotiation** in this client. It calls the MAM
  module directly; `urn:xmpp:mam:2` is assumed (`query_mam`, `:904-959`).
  (The TS/openclaw reference does a feature probe; here fail-closed is by
  exception, see below.)
- Query (built by `nbxmpp/modules/mam.py:116-168`):
  ```xml
  <iq type='set' to='<bare|self>' id='...'><query xmlns='urn:xmpp:mam:2' queryid='<uuid4>'>
    <x xmlns='jabber:x:data' type='submit'>
      <field var='FORM_TYPE' type='hidden'><value>urn:xmpp:mam:2</value></field>
      <field var='with'><value>peer@example.org</value></field>            <!-- jid-single -->
      <field var='start'><value>YYYY-MM-DDTHH:MM:SSZ</value></field>       <!-- optional -->
      <field var='end'><value>YYYY-MM-DDTHH:MM:SSZ</value></field>         <!-- optional -->
    </x>
    <set xmlns='http://jabber.org/protocol/rsm'><max>50</max>
      <after>ARCHIVE-ID</after></set>                                      <!-- optional -->
  </query></iq>
  ```
  Caller kwargs: `jid=self._jid, queryid, with_=bare, max_=50`, optional
  `start`/`end` (datetime) and `after` (archive UID) (`:935-944`). Only `after`
  is ever sent (no `before`); scroll-older uses `end=` (`:2249-2271`).
- Results: `_on_message` MAM branch appends
  `(body, direction, ts, mam.id, quick, commands, stanza_id, replace_id)` to
  `_pending_mam_queries[queryid]['buffer']`; IQ completion in
  `_on_mam_query_done` reads `result.complete` and `result.rsm.last`
  (`:1194-1226,961-977`).
- Watermark/backfill (`load_history_from_mam`, `:2204-2239`):
  watermark = `get_latest_mam_id()` (`SELECT mam_id ... WHERE mam_id IS NOT
  NULL ORDER BY timestamp DESC LIMIT 1`) → forward catch-up `after=<watermark>`
  with `start=None`. No watermark → time overlap
  `start = latest_timestamp - 7 days` (`_overlap_timestamp`, `:2241-2247`).
  Forward pagination while `not complete and rsm_last`:
  `query_mam(start=self._mam_catchup_start, after=rsm_last, ...)`
  (`_on_mam_catchup_page`, `:2365-2380`). Batch end emits
  `history-complete(False)`.
- Dedupe by archive id: `attach_mam_to_request_id` → else
  `attach_mam_to_recent_message` → else `record_message` (`INSERT OR IGNORE`,
  `UNIQUE(bare_jid,mam_id)`); `cleanup_mam_shadow_duplicates` deletes un-MAM'd
  shadows within 30 s after a MAM row (`xmpp_history.py:456-618`).
- Fail-closed: `query_mam` returns `None` when not connected; on exception it
  pops the pending entry and invokes `callback([], False, None)` (`:925-958`).
  `load_history_from_mam` returns `False` (no `history-complete`) when
  disconnected or a query is already in flight (`:2218-2219`).

## 6. XEP-0050 ad-hoc + XEP-0004 forms

- Client wrapper `XmppCommandClient` (`xmpp_commands.py:19-62`); commands are
  built by nbxmpp's `AdHoc` module.
- **Discovery** (`request_command_list`, `nbxmpp/modules/adhoc.py:39-64`) →
  `<iq type='get' to='agent@example.org'><query
  xmlns='http://jabber.org/protocol/disco#items'
  node='http://jabber.org/protocol/commands'/></iq>`. Response
  `<item jid= node= name= [sessionid=]/>` → `AdHocCommand` namedtuple
  (`nbxmpp/structs.py:782-791`).
- **Inline announcements** in a message are parsed manually
  (`_parse_inline_commands`, `xmpp_client.py:1370-1407`):
  ```xml
  <message><query xmlns='http://jabber.org/protocol/disco#items'
                  node='http://jabber.org/protocol/commands'>
    <item jid='agent@example.org' node='cmd:abc:0' name='Allow'
          style='success' expires-at-ms='1699999999000'/>
  </query></message>
  ```
  Keys kept: `jid, node, name, style, expires_at_ms`; quick responses come from
  `<response xmlns='urn:xmpp:quick-response:0'|'urn:xmpp:tmp:quick-response'
  value= label= [expires-at-ms=][style=]/>` and legacy
  `<reference type='action'><body>value</body></reference>`
  (`_parse_quick_responses`, `:1341-1368`; namespaces `:78,161`).
- **Execute** (`execute_command`, `adhoc.py:66-126`; `_make_command`,`:129-139`):
  ```xml
  <iq type='set' to='agent@example.org/res'>
    <command xmlns='http://jabber.org/protocol/commands'
             node='cmd:abc:0' action='execute' [sessionid='...']/>
  </iq>
  ```
  Default `action='execute'`; `attrs` always include `node`, `xmlns`,
  `action`, and `sessionid` when known (`adhoc.py:77-79`).
- **Form submit** (same IQ, form child; `XmppCommandFormDialog._submit`
  `xmpp_commands.py:196-219`, `SimpleDataForm(type_='submit')`):
  ```xml
  <command xmlns='http://jabber.org/protocol/commands' node='...'
           action='next' sessionid='...'>
    <x xmlns='jabber:x:data' type='submit'>
      <field var='mode' type='list-single'><value>on</value></field>
      <field var='minutes' type='text-single'><value>10</value></field>
    </x>
  </command>
  ```
  Rendering maps field types: `hidden` kept & re-submitted, `fixed` read-only
  row, `boolean`→SwitchRow, `list-single`→ComboRow (options are `(value,label)`
  from `iter_options()`), `text-multi`→TextView, `text-private`→PasswordEntryRow,
  else EntryRow (`xmpp_commands.py:125-215`).
- Multi-stage: `next_action_for(command)` = `command.default` if it is
  NEXT/COMPLETE, else NEXT if offered, else COMPLETE; `is_completed` =
  `status == COMPLETED` (`:272-281`). Response parsed into `AdHocCommand` with
  `status, sessionid, data (<x>), actions, default, notes`
  (`adhoc.py:85-126`).
- **Selection emitted on choose**: an inline command item (has `jid`+`node`) is
  executed as an ad-hoc IQ, not text (`chat_window.py:4619-4621,4644-4735`): a
  minimal `AdHocCommand(jid=JID(jid), node=node, name=name)` →
  `client.execute(adhoc, on_success, on_error)` (action defaults to `execute`).
  A pure quick-response (no node) is sent as a normal chat message
  `send_text(value)` (`xmpp_client.py:2111-2135`).

## 7. SQLite history schema

Own DB `<userdir>/xmpp_history.db`, never `llm`'s logs.db
(`xmpp_history.py:33-42`); thread-local connection, `PRAGMA journal_mode=WAL`,
lazy `_migrate_db` via `PRAGMA table_info` (`:47-106`).

```sql
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bare_jid TEXT NOT NULL,
  body TEXT NOT NULL,
  direction TEXT NOT NULL,          -- 'in' | 'out'
  timestamp TEXT NOT NULL,          -- ISO-8601 UTC
  mam_id TEXT,                      -- XEP-0313 archive UID (dedupe)
  quick_responses TEXT,             -- JSON list
  commands TEXT,                    -- JSON list
  request_id TEXT,                  -- original stanza id (XEP-0308 target)
  attachment_url TEXT, attachment_mime_type TEXT, attachment_duration REAL,
  attachment_local_path TEXT, attachment_state TEXT,
  was_encrypted INTEGER NOT NULL DEFAULT 0,
  encryption_namespace TEXT,
  UNIQUE(bare_jid, mam_id)
);
CREATE INDEX idx_messages_jid_ts      ON messages(bare_jid, timestamp);
CREATE INDEX idx_messages_jid_request ON messages(bare_jid, request_id);
```

- Insert `INSERT OR IGNORE` keyed by `UNIQUE(bare_jid,mam_id)`; if the
  `mam_id` exists, only COALESCE-update metadata/request_id and return False
  (`:125-151`).
- Fold rules recap: live correction → `UPDATE ... WHERE bare_jid AND
  request_id` (`update_by_request_id`); MAM re-attach prefers
  `request_id` match then nearest-timestamp within 120 s, and never re-decrypts
  an OMEMO row (`attach_mam_to_request_id` / `_recent_message` /
  `attach_mam_to_decrypted_request`, `:462-571`).
- Pending-action expiry: `expires_at_ms` if present, else 15 min (30 min for
  approvals) from message timestamp (`:400-429`). `get_recent` returns the
  newest `limit` re-sorted ascending (`:228-240`).

## 8. Account dialog + credential storage

- Validation-before-persist (`xmpp_account_dialog.py:112-172`): on Connect it
  builds a **throwaway** `XmppSession(jid, password, auto_reconnect=False)`,
  subscribes `state-changed` + `session-error`, and only on
  `STATE_CONNECTED` calls `save_account(jid, password, omemo_enabled)`; on
  failure the error is shown and input is preserved (`:128-166`). A 20 s
  `GLib.timeout_add_seconds` probe timeout shows "Connection timed out" and
  cleans up (`:137-142,168-172`). Edit mode keeps an existing account; an empty
  password keeps the stored one (`:36-37,115-118`).
- Storage (`xmpp_account.py`): JID/omemo/label as JSON in
  `<userdir>/xmpp_account.json`; **password never on disk** — system keyring
  `KEYRING_SERVICE = 'gtk-llm-chat-xmpp'`, `keyring.set_password(service, jid,
  password)` (`:22,57-64`). `load_account` returns `None` if the keyring lacks
  the password even when the JID file exists (`:68-91`). No env override and no
  explicit `chmod`/perms call in this module — file perms follow the process
  umask; the keyring is the confidentiality boundary, not file mode.

## GOTCHAS

- Reuse the same nbxmpp `Client` across reconnects or XEP-0198 resume is never
  requested and the server hibernates zombie sessions (`:286-298`); a wrong
  password arrives on `disconnected`, not `connection-failed` (`:508-521`).
- Do not add `presence` or send messages before roster+initial presence, or the
  server queues them (`:500-506,599-600`). Carbons `<enable/>` must be a direct
  iq child, not inside `<query>` (`:606-610`).
- `add_done_callback(..., weak=False)` is mandatory for nbxmpp tasks; the
  default weakref lets local callbacks be GC'd and the query hangs silently
  (`:945-952`).
- No XEP-0184 receipts and no XEP-0203 `<delay>` parsing in this client;
  no MAM disco#info preflight. Delay only arrives via `properties.mam.timestamp`
  (epoch float). Do not assume a date separator exists.
- XEP-0308 dedupe hinges on the *original* stanza id being stored as
  `request_id`; if it is dropped, every streaming edit becomes a separate row
  and never collapses with MAM (`:1888-1912,2273-2318`).
- Presence "online" is set membership of resources; priority/show are not
  aggregated beyond the BUSY/AWAY heuristic (`:848-876`).
- History is only trustworthy when `mam_id IS NOT NULL`; unverified live rows
  are provisionally deduped by body+time window, which can misattach repeated
  identical bodies (nearest-timestamp wins, `xmpp_history.py:536-552`).
- OMEMO send path is fail-closed: if the engine/manager is not ready, the send
  is aborted and marked failed rather than leaking plaintext (`:1431-1444`).
