# OpenClaw XMPP — wire-format & algorithm reference

Source repo: `/home/icarito/Proyectos/openclaw-xmpp` (TypeScript `@openclaw/xmpp`).
Scope: exact XMPP stanzas, PEP nodes, payloads and client algorithms a Godot-3
GDScript client must reproduce. Citations are `file:line` in that repo.
DM archive + PEP service = agent bare JID. Gateway full JID =
`<account.jid>/<account.resource>` (`src/send.ts:647`, `src/commands.ts:318`).
`<body>` is plain text; markdown is stripped (`PORT-NOTES.md:157-160`).

## 1. XEP-0313 MAM
### Query / features checked
Preflight probes bare JID + MUC domain with disco#info; MAM on only if
`<feature var='urn:xmpp:mam:2'/>` present (var split on spaces). Cached per
account, fail-closed; only mam:2 is checked, no `#extended`/`mam:1`
(`src/preflight-features.ts:35-55,88-116`). Query (`buildMamQuery`,
`src/mam.ts:85-118`):
```xml
<iq type='set' to='bot@example.org' id='mam-1-abc'>
  <query xmlns='urn:xmpp:mam:2' queryid='mam-1-abc'>
    <x xmlns='jabber:x:data' type='submit'>
      <field var='FORM_TYPE' type='hidden'><value>urn:xmpp:mam:2</value></field>
      <field var='with'><value>peer@example.org</value></field>       <!-- optional -->
      <field var='start'><value>2026-10-05T00:00:00.000Z</value></field>
      <field var='end'><value>2026-10-05T12:00:00.000Z</value></field>
    </x>
    <set xmlns='http://jabber.org/protocol/rsm'>
      <max>50</max>
      <after>ARCHIVE-ID</after>     <!-- OR <before></before> empty = fetch-latest -->
    </set>
  </query>
</iq>
```
`max` default 50, `maxPages` 4, IQ timeout 30 s; RSM mandatory in practice
(Prosody caps at 50) (`src/mam.ts:3-6,24-25,209-210`). Only one of
`<after>`/`<before>` is emitted; empty `<before/>` = latest page
(`src/mam.ts:103-105`). Timestamps via `toISOString()` (`src/mam.ts:100-101`).
### Results and archive ids
Results are separate `<message>` stanzas correlated by `queryid`; caller feeds
them to the MAM client while the IQ is in flight — never inbound chat
(`src/mam.ts:8-11,220-227`):
```xml
<message>
  <result xmlns='urn:xmpp:mam:2' queryid='mam-1-abc' id='ARCHIVE-ID'>
    <forwarded xmlns='urn:xmpp:forward:0'>
      <delay xmlns='urn:xmpp:delay' stamp='2026-10-05T11:00:00Z'/>
      <message type='chat' from='peer@example.org/res'>
        <body>text</body>
        <stanza-id xmlns='urn:xmpp:sid:0' by='bot@example.org' id='ARCHIVE-ID'/>
        <origin-id xmlns='urn:xmpp:sid:0' id='sender-origin-id'/>
      </message>
    </forwarded>
  </result>
</message>
<iq type='result'><fin xmlns='urn:xmpp:mam:2' complete='true'>
  <set xmlns='http://jabber.org/protocol/rsm'>
    <first>ID</first><last>ID</last><count>N</count></set></fin></iq>
```
`complete` defaults true unless `complete='false'`; `stable` only when
`stable='true'`; `fin` may be under `query` (`parseMamFin`,
`src/mam.ts:153-169`). Archive id = XEP-0359 `<stanza-id by id/>` inside the
forwarded message; fallback `<result id>` with `by:""` (`src/mam.ts:129-136`).
Live equivalent `stanzaArchiveId()` = stanza-id else origin-id with `by:""`
(`src/mam.ts:189-194`). Composite key `"${by}\u0000${id}"` (ids are scoped to
the assigning JID) (`src/mam.ts:183-186`). `catchup` sorts each page by
`delayMs`, dedupes by composite key or `origin:<originId>`, stops on
`complete`/no-`last`/`last===after`, else `after=last` (`src/mam.ts:178-181,255,327-338`).

## 2. MAM watermark / backfill (`src/mam-watermark.ts`)
File `<OPENCLAW_STATE_DIR>/channel-cache/xmpp/<accountId>-mam-watermark.json`,
`{version:1, peers:{...}}` (`src/mam-watermark.ts:27-36,183-205`). Entry =
`{last:{by,id}, at, seen:[{key,at}]}`; `seen` cap 500, TTL 7 d
(`src/mam-watermark.ts:12-17,29-30,130-140`). Peer keys `dm:<bare>` /
`room:<roomJid>` (`src/mam-watermark.ts:43-55`). **already seen** ⇔ composite
`by\0id` in `seen` within TTL (`isSeen` `85-91`). `setLast` advances anchor +
marks seen; `markSeen` marks without moving anchor (`94-111`). Catch-up calls
`setLast` for every recovered message (`src/history-context.ts:87-109`). Purged
anchor degrades to fetch-latest exactly once: `now-anchorAt>windowMs`
(`src/mam.ts:291-298`) or IQ error matching
`item-not-found|not-found|gone|purged|no longer|invalid-anchor`
(`src/mam.ts:172-176,315-325`) → `after=undefined, before=""`. Window =
`start ?? now-windowMs`, sent as `start` only while paging from an anchor
(`src/mam.ts:287,312`). Live/replay (`decideArchiveReplay`,
`src/history-context.ts:23-32`, `src/monitor.ts:759-782`): `replay` when MAM
enabled + archive id + `isSeen`; `stale` when older than the 5-min guard;
else `fresh`. Replays dropped; fresh stanzas advance the watermark.

## 3. PEP + avatars
Namespaces `http://jabber.org/protocol/pubsub` (+`#event`,`#owner`)
(`src/pep.ts:22-24`); avatar nodes `urn:xmpp:avatar:data` /
`urn:xmpp:avatar:metadata` (`src/avatar.ts:21-22`). Data item id **is the sha1
hex of the raw bytes**, value base64; metadata `<info id bytes type/>`
(`src/avatar.ts:86-126`):
```xml
<iq type='set' id='avatar-data-...'><pubsub xmlns='http://jabber.org/protocol/pubsub'>
  <publish node='urn:xmpp:avatar:data'><item id='<sha1hex>'>
    <data xmlns='urn:xmpp:avatar:data'>BASE64...</data></item></publish></pubsub></iq>
<iq type='set' id='avatar-meta-...'><pubsub xmlns='http://jabber.org/protocol/pubsub'>
  <publish node='urn:xmpp:avatar:metadata'><item id='<sha1hex>'>
    <metadata xmlns='urn:xmpp:avatar:metadata'>
      <info id='<sha1hex>' bytes='12345' type='image/png'/></metadata></item></publish></pubsub></iq>
```
Order data→metadata→vCard, vCard best-effort; sha1 over raw bytes hex-encoded,
base64 is only wire encoding; max 8 MB; MIME sniffed PNG/JPEG/GIF/WebP
(`src/avatar.ts:28,54-72,157-186`). XEP-0153: every presence re-announces
`<x xmlns='vcard-temp:x:update'><photo><sha1hex></photo></x>`
(`src/avatar.ts:44-52`, `src/telemetry.ts:79-87,111-119`). Fetch/subscribe:
```xml
<iq type='get' to='bot@example.org'><pubsub xmlns='http://jabber.org/protocol/pubsub'>
  <items node='urn:xmpp:avatar:data'/></pubsub></iq>
<iq type='set' to='bot@example.org'><pubsub xmlns='http://jabber.org/protocol/pubsub'>
  <subscribe node='urn:xmpp:avatar:metadata' jid='me@example.org'/></pubsub></iq>
```
(`pepFetch` `src/pep.ts:188-242`; `pepSubscribe` `252-291`.) Client flow: read
`info.id` from metadata, request data with that item id, cache base64 by hash.
Inbound event (`parsePepEvent` `src/pep.ts:424-465`): `<message><event
xmlns='...#event'><items node='...'><item id='<hash>'/>` or
`<retract id='<hash>'/>`.

## 4. Telemetry (`src/telemetry.ts`)
PEP node **`urn:openclaw:telemetry:0`**, item id `current`, access_model
presence, persist_items true, max_items 1. Payload is **packed XML, not JSON**
(`src/telemetry.ts:41,152-174`):
```xml
<iq type='set' id='tel-...'><pubsub xmlns='http://jabber.org/protocol/pubsub'>
  <publish node='urn:openclaw:telemetry:0'><item id='current'>
    <telemetry xmlns='urn:openclaw:telemetry:0' activity='available' availability='available'>
      <context used='12000' max='131072' scope='active' maxSource='config'/>
      <tokens total='..' input='..' output='..' requests='5' scope='session'/>
      <cost usd='0.0012' scope='last-request'/>
      <session-cost usd='0.0040' scope='session'/>
      <day-cost usd='0.0100' scope='day-local'/>
      <model>deepseek/deepseek-v4-pro</model><tool>exec</tool><session status='running'/>
    </telemetry></item></publish>
  <publish-options><x xmlns='jabber:x:data' type='submit'>
    <field var='FORM_TYPE' type='hidden'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>
    <field var='pubsub#persist_items'><value>true</value></field>
    <field var='pubsub#max_items'><value>1</value></field>
    <field var='pubsub#access_model'><value>presence</value></field>
  </x></publish-options></pubsub></iq>
```
`activity` ∈ `available|processing|busy|paused|pending`; `availability` ∈
`available|busy|away` (`src/telemetry.ts:50-65,122-149`). Republished only on
change or context delta ≥500 tokens (`43,186-201`). The payload has **no JID**:
a client learns the agent from the PEP `<message from>` (bare) or directed
`<presence to='peer'/>` (`src/telemetry.ts:108-120`); direct IQ target is
`<jid>/<resource>`. Agent detection = caps advertise the telemetry `+notify`
feature (§5) + reachable PEP; subscribe to the node. JSON PEP hook nodes
(`src/hooks/pep-events.ts:20-22,49-55`): the JSON is the **text content of an
element whose namespace is the node**, plus `version="1"` —
`urn:openclaw:hooks:activity:0|approval:0|progress:0`, fields `contractVersion:1,
event, state, sessionKey, originJid, target, timestamp` (+ `pendingCount` /
`approvalId,stanzaId,jid,expiresAtMs,decision` / `detail`).

## 5. XEP-0115 caps
Presence: `<c xmlns='http://jabber.org/protocol/caps' hash='sha-1'
node='https://github.com/openclaw/openclaw' ver='<base64>'/>`
(`src/telemetry.ts:75-88`, `src/send.ts:268-293`). Identity
`category=automation type=command-list name=OpenClaw` (`src/xep-0050.ts:36-37`).
Features (sorted before hashing, `src/xep-0050.ts:38-43`):
`http://jabber.org/protocol/commands`, `...disco#info`, `...disco#items`,
`urn:openclaw:telemetry:0+notify`. `ver` = **base64(sha1(verification-string))**,
string = `` `${category}/${type}//${name}<` `` then each `` `${feature}<` ``
(`src/telemetry.ts:69-73`). Not hex; note the empty node `//` before the name.
An agent = presence whose caps node is that URL and/or whose features include
the command + telemetry namespaces (`src/xep-0050.ts:131-176`).

## 6. XEP-0050 + XEP-0004 + XEP-0439 + selection IQ
### Discovery / execute / form / submit
```xml
<iq type='get' to='bot@example.org/resource'><query
  xmlns='http://jabber.org/protocol/disco#items' node='http://jabber.org/protocol/commands'/></iq>
<!-- result items: <item jid='<full JID>' node='<node>' name='<name>'/> -->
<iq type='get' id='di1'><query xmlns='http://jabber.org/protocol/disco#info' node='compact'/>
<!-- <identity category='automation' type='command-node' name='Session: compact'/> + feature jabber:x:data -->
<iq type='set' id='c1' to='bot@example.org/resource'><command
  xmlns='http://jabber.org/protocol/commands' node='elevated' action='execute'/></iq>
```
Items from `handleDiscoItems` (`src/xep-0050.ts:111-129`); per-node disco#info
`163-175`. Catalogue: status, credit, help, context, compact, reset, new,
model, abort, elevated (`HOOKS.md:68-82`). `cmd:*`/`q:*` are transient, never in
disco#items. 0 params → immediate `status='completed'` + `<note type='info'>`
(+ optional result form); >0 params → `status='executing'`, `sessionid='oc-cmd-...'`
and a form (`src/xep-0050.ts:206-208,256-274,276-296,335-360`):
```xml
<command xmlns='http://jabber.org/protocol/commands' node='elevated'
         status='executing' sessionid='oc-cmd-...'>
  <x xmlns='jabber:x:data' type='form'>
    <title>Elevated: temporary session bypass</title>
    <field var='mode' type='list-single' label='Modo'><value>status</value>
      <option label='on'><value>on</value></option></field>
    <field var='minutes' type='text-single' label='Minutos'><value>10</value></field>
  </x></command>
<!-- submit: same node+sessionid, action='submit', <x type='submit'> -->
```
Result form is an **additional child** of `status='completed'`; prefer it over
`<note>` (`src/xep-0050.ts:331-360`, `HOOKS.md:168-184`). Errors:
`<iq type='error'><command status='canceled'><error type='cancel|auth|modify'/>`
(`src/xep-0050.ts:362-386`). Forms namespace `jabber:x:data`; boolean → `1`/`0`;
`<option>` only on list-* (`src/xep-0004.ts:8,38-83`).
### Item schema, selection IQ
Each button = transient node **`cmd:<stanzaId>:<index>`**, TTL **15 min**
(`src/command-node-registry.ts:8`, `src/send.ts:630-648`). Item attrs `jid`
(agent full JID), `node`, `name` (label ≤20 chars + `…`), optional `style`,
optional `expires-at-ms` (`src/outbound-render.ts:61-68,102-117`). Selection IQ:
```xml
<iq type='set' id='b1' to='bot@example.org/resource'><command
  xmlns='http://jabber.org/protocol/commands' node='cmd:oc-abc:0' action='execute'/></iq>
<!-- approval/action button; ask_question option uses node='q:<questionId>:<index>' -->
```
Plugin maps node back to literal command text and runs it; reply
`completed`+`<note type='info'>Command submitted.</note>`, expired →
`<note type='warn'>Command expired.</note>` (`src/commands.ts:244-280,411-437`,
`HOOKS.md:278-288`). Text fallback also accepts `"1"`, the label, or the raw
value (`src/send.ts:638-645`, `src/command-node-registry.ts:70-97`).
### XEP-0439 quick responses
`urn:xmpp:tmp:quick-response`, emitted with the disco query
(`src/outbound-render.ts:70-128`):
```xml
<message type='chat' to='operator@example.org' id='oc-...'>
  <body>🔒 rm -rf /tmp/x
Responde: /approve deadbeef allow-once | allow-always | deny</body>
  <reference xmlns='urn:xmpp:tmp:quick-response' type='action'><body>Allow Once</body></reference>
  <response xmlns='urn:xmpp:tmp:quick-response' value='/approve deadbeef allow-once'
            label='Allow Once' style='success' expires-at-ms='1758900000000'/>
  <query xmlns='http://jabber.org/protocol/disco#items' node='http://jabber.org/protocol/commands'>
    <item jid='bot@example.org/openclaw' node='cmd:oc-...:0' name='Allow Once'
          style='success' expires-at-ms='1758900000000'/></query>
</message>
```
`<response>` attrs `value` (literal command text), `label`, non-standard `style`
∈ `primary|secondary|success|danger`, optional string `expires-at-ms`
(`src/outbound-render.ts:92-100`). Both representations emitted because servers
strip the disco extension; clients understanding command-items prefer XEP-0050
(`121-127`).

## 7. Approval cards
Body text (`buildCompactExecApprovalText`, `src/approval-text.ts:47-77`):
```
⚠️ <warning ≤200>
🔒 <command ≤220>
cwd <≤60> · caduca en <Ns|Nm>
Responde: /approve <slug8> allow-once | allow-always | deny
```
`slug8` = first 8 chars of the approval UUID (`src/approval-handler.runtime.ts:370,392`);
expiry <90 s → `Ns`, else `Nm` (`src/approval-text.ts:30-35`); title = one-line
command ≤80 (`18-23`). `expires-at-ms` comes from `request.expiresAtMs`, copied
to each `<response>`/`<item>`; if absent defaults 15 min
(`src/approval-handler.runtime.ts:378`, `src/send.ts:626-628`,
`src/outbound-render.ts:99,113-115`, `src/command-node-registry.ts:8`). **Client
retires any action/card whose `expires-at-ms` passed locally without waiting for
a correction** (`HOOKS.md:186-194`). Lifecycle: card persisted with
`stanzaId=messageId`, node `cmd:<stanzaId>`, `expiresAt`, optional
`sessionKey/commandText` (`src/approval-card-registry.ts:11-22`,
`src/approval-handler.runtime.ts:609-622`). Resolution/expiry edits the card
**via XEP-0308**: `<message><body>..</body><replace
xmlns='urn:xmpp:message-correct:0' id='<stanzaId>'/></message>`; resolved text
starts `✅`/`🚫`, expired `⌛` (`src/outbound-render.ts:130-142`,
`src/approval-handler.runtime.ts:408-422,483-488,644-655`). On restart every
persisted card is reconciled closed (`⌛ ... (reconciliada tras reinicio)`) and
dropped (`src/approval-card-registry.ts:91-128`). Reprompt at ~2/3 remaining
time (min 30 s); one in-flight approval per session
(`src/approval-handler.runtime.ts:105-130,572-595`). Only delivered when the
account has non-empty `allowFrom` and `inlineButtons != "off"`; otherwise plain
text (`src/approval-handler.runtime.ts:275-280`, `src/send.ts:592-622`).

## 8. Stanza normalization
`src/normalize.ts`: `bareJid` strips `/resource` (`7-10`); `isGroupJid` =
lowercased bare ends with `@<mucDomain>` (`12-17`); `looksLikeXmppTargetId`
regex `^[^\s@/]+@[^\s@/]+(\/[^\s]*)?$` (`24-32`); `normalizeXmppMessagingTarget`
strips `xmpp:`/`channel:`/`user:` (`34-54`); allow entries lowercased bare JID
(`82-101`). `src/protocol.ts`: `splitForLimit` at `XMPP_MAX_BODY=4000`
(`\n\n`→`\n`→space→hard, `21-38`); `isStaleDelayedStanza` XEP-0203 delay >5 min
stale (`22,45-51`); `markdownToPlain` (`59-71`); XEP-0280
`classifyCarbonStanza` — `<sent/>` ignored, `<received/>` unwrapped from
`<forwarded><message>` (`281-291`); XEP-0359 helpers; XEP-0184/0333/0334
helpers (`207-264`); `extractOobUrl`/`stripInlineOobMarkup` recover the OOB URL
from an OMEMO plaintext body containing literal `<x xmlns='jabber:x:oob'>`
(`130-151`); `messageMentionsBot` XEP-0372 else nick regex (`90-100`);
`extractReply` XEP-0461 (`106-115`). Monitor drops MUC self-echo and
unmentioned group messages (`src/monitor.ts:753-757,822-824`).

## GOTCHAS
1. RSM `<max>` is mandatory in practice; Prosody caps at 50 (`src/mam.ts:3-6`).
2. Archive ids are scoped to the assigning JID — use the composite `(by,id)` key
   (`src/mam-watermark.ts:38-41`).
3. MAM results are `<message>` stanzas correlated by `queryid`; route to the MAM
   layer before treating as chat (`src/mam.ts:8-11,220-227`).
4. Empty `<before/>` = fetch-latest; a purged anchor degrades to it once
   (`src/mam.ts:103-105,291-298`).
5. `ver` is base64 of a sha1 (not hex); verification string is
   `category/type//name<` (double slash, trailing `<`) (`src/telemetry.ts:69-73`).
6. Avatar hash = hex sha1 of raw bytes; item id = that hash; payload = base64 —
   do not hash the base64 or emit base64 as the id (`src/avatar.ts:170-179`).
7. The XEP-0153 hash must appear in every presence or clients never refresh
   (`src/avatar.ts:43-52`).
8. Telemetry is packed XML; only `urn:openclaw:hooks:*:0` nodes are JSON
   (`src/telemetry.ts:122-149`, `src/hooks/pep-events.ts:49-55`).
9. No JID inside the payload — use PEP/presence `from`; direct IQ target is
   `<jid>/<resource>` (`src/commands.ts:318`).
10. `urn:xmpp:tmp:quick-response` is a temporary XEP; Cheogram ignores it and
    uses the disco#items query — support both (`src/outbound-render.ts:5-7,121-127`).
11. Card buttons expire in 15 min by default and must be dropped at
    `expires-at-ms`; pressing after expiry yields `Command expired.`
    (`src/command-node-registry.ts:8`, `src/commands.ts:276`).
12. Cards are retired with XEP-0308 `<replace>`, not a retract/delete
    (`src/approval-handler.runtime.ts:644-655`).
13. After restart, orphaned cards are reconciled closed, not replayed
    (`src/approval-card-registry.ts:91-128`).
14. Approvals need non-empty `allowFrom` + `inlineButtons != "off"`; MUC cards
    redirect to `approvalDmJid` when configured
    (`src/approval-handler.runtime.ts:275-300`).
15. `<body>` is always plain text; buttons live out-of-body, so text-only
    clients only see the fallback (`PORT-NOTES.md:157-160`, `src/send.ts:185-187`).
16. XEP-0280 `<sent/>` carbons must be ignored entirely (`src/protocol.ts:275-291`).
