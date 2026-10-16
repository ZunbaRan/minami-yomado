# Minami Yomado demo: reconcile an invoice and write a review memo

Status: Preview/TextEdit rehearsal completed on 2026-10-16 with two synthetic PDFs and a saved $130 discrepancy memo. The first rehearsal also exposed disruptive viewer resizing/reopening; the presentation flow below now keeps a compact, persistent viewer. Finder presentation and Save dialogs still require separate rehearsal.

## The story

“Give the agent its own visible workspace. Watch it compare evidence across applications and produce a useful result, while your physical desktop remains available.”

The task is to compare a mock purchase order with a supplier invoice, find two deliberate discrepancies, and save a short review memo. The whole-desktop PiP keeps both evidence documents and the evolving memo visible in one view. Switching applications or opening a dialog does not require choosing a new app window to mirror.

Use synthetic local files, with no login, network, private business data, or external messages. This keeps the task repeatable and gives the audience a checkable answer. The demo is an interface/workspace demonstration, not accounting advice.

## Proposed inputs and expected result

Prepare `Minami Yomado Demo/` with two one-page PDFs and an empty `Output/` directory:

| Item | Purchase order | Invoice |
| --- | --- | --- |
| Monitor stands | 10 × $40 = $400 | 12 × $40 = $480 |
| USB-C docks | 5 × $100 = $500 | 5 × $100 = $500 |
| Delivery | Included, $0 | $50 |
| Total, before tax | $900 | $1,030 |

Both documents explicitly exclude tax. Expected findings: two extra stands ($80) and an unapproved delivery charge ($50), for a total discrepancy of **$130**. The memo should request clarification before approval; it should not contact the supplier.

Suggested output: `Output/invoice-review.rtf`, containing a short comparison table/list, the $130 difference, and the two questions to ask the supplier. A saved file makes the result tangible.

## Visible workspace

Use a 2240×1080 virtual display named `Invoice Review`. Arrange two separate Preview PDF windows across the left two-thirds and a TextEdit memo window on the right. Finder briefly shows the task folder and later the saved output. Use explicit task window IDs; do not move other Preview, Finder or TextEdit windows.

On the physical screen, keep the presenter’s notes open alongside a compact desktop PiP (480×300 by default, or the user’s last chosen size). Let the presenter resize it when desired; do not override their size. Keep this same viewer open throughout the task. PiP is read-only: move and resize its frame, but do not imply that clicking its pixels controls the remote workspace.

## Three-to-four-minute presentation

| Beat | What the audience sees | What it demonstrates |
| --- | --- | --- |
| 0:00–0:25 | Give Codex the task; a named workspace and its PiP appear. | Workspace setup through MCP. |
| 0:25–1:10 | Two PDF windows move into view; Codex inspects quantities and charges. | Several documents remain visible in one desktop composition. |
| 1:10–2:20 | The agent switches to TextEdit and writes the findings while both PDFs remain visible. | Application automation by Minami, observation by Minami Yomado. |
| 2:20–2:50 | Save the memo into the task folder; show the file in Finder. | A real cross-application result, not a synthetic counter. |
| 2:50–3:20 | Leave the completed documents and memo visible in the same PiP. | Persistent observation across the entire task. |
| 3:20–3:50 | Restore task windows and stop the virtual display. | Explicit ownership and cleanup. |

Timing is a presentation target, not a measured agent runtime. If the task runs longer, explain the handoff between the workspace manager and input tools instead of rushing tool execution.

## Copyable demo prompt

> Use Minami Yomado to create a 2240×1080 workspace called “Invoice Review” and show its whole-desktop PiP on my physical display. Use the compact default or my saved size; keep one viewer open and do not enlarge or reopen it during the task. In the prepared “Minami Yomado Demo” folder, open purchase-order.pdf and invoice.pdf in separate Preview windows. Use Minami computer-use to compare them visually, then write a concise discrepancy report in TextEdit and save it as Output/invoice-review.rtf. Arrange the two PDFs and report so I can follow all three together. Move only the windows opened for this task. Do not send anything externally. Keep the workspace and PiP open when the report is saved so I can show the result.

Only demonstrate closing/reopening the viewer if the presenter explicitly asks. Routine work does not need this.

Finish with a second instruction:

> Restore the windows moved for Invoice Review, close its PiP, and stop its virtual display. Confirm that my physical display layout is unchanged.

## Rehearsal gate

- Create the PDFs and demo folder, then rehearse this exact prompt once on the presentation machine. Confirm separate Preview windows, readable PDF zoom, background input, and the TextEdit Save dialog. An untested Save dialog is the biggest avoidable interruption.
- Keep documents entirely inside one physical display before moving them; Minami Yomado rejects partly off-screen/spanning starting positions.
- Confirm the relevant dialogs actually appear on the virtual display. macOS may put some dialogs on the physical screen; the PiP cannot show content from another display.
- Verify the result is $130 and the file exists before declaring success. Capture a backup recording only after a complete successful rehearsal.
- Do not claim separate keyboard/mouse sessions or guaranteed simultaneous typing. Virtual displays share the macOS login and input session. The earlier tests verify specific Minami background interactions, not universal input isolation.

Avoid making the managed browser the first demo: its host may hide windows even while window-level capture works. Native visible document windows make the value of whole-desktop viewing easier to demonstrate reliably.
