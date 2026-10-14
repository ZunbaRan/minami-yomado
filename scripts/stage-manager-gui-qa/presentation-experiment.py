"""Independent one-change comparisons on disposable macOS runners only."""
import os
import sys
from pathlib import Path
if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Disposable GitHub-hosted runner only")
root, variant = Path(sys.argv[1]), sys.argv[2]
def replace(file, old, new):
    p = root / file
    s = p.read_text()
    if s.count(old) != 1:
        raise SystemExit("Expected exact baseline sequence once: " + file)
    p.write_text(s.replace(old, new))
if variant == "early-primary-experiment":
    replace("app/Yomado.m", """        backing:NSBackingStoreBuffered defer:NO];
    self.window.contentView = [[YMDocumentView alloc]""", """        backing:NSBackingStoreBuffered defer:YES];
    self.window.collectionBehavior = NSWindowCollectionBehaviorPrimary;
    self.window.contentView = [[YMDocumentView alloc]""")
elif variant == "sync-activation-experiment":
    replace("app/PanelPresentation.m", """    [NSApp activate];
    [window makeKeyAndOrderFront:nil];""", """    [window makeKeyAndOrderFront:nil];""")
    replace("app/PanelPresentation.m", """    if (!window) return;
    dispatch_async""", """    if (!window) return;
    [NSApp activate];
    dispatch_async""")
elif variant == "legacy-activation-experiment":
    replace("app/PanelPresentation.m", "    [NSApp activate];", "    [NSApp activateIgnoringOtherApps:YES];")
elif variant == "managed-primary-experiment":
    replace("app/PanelPresentation.m", """        | NSWindowCollectionBehaviorAuxiliary | NSWindowCollectionBehaviorCanJoinAllApplications;""", """        | NSWindowCollectionBehaviorAuxiliary | NSWindowCollectionBehaviorCanJoinAllApplications
        | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorTransient
        | NSWindowCollectionBehaviorIgnoresCycle;""")
    replace("app/PanelPresentation.m", """        | NSWindowCollectionBehaviorPrimary;""", """        | NSWindowCollectionBehaviorPrimary | NSWindowCollectionBehaviorManaged
        | NSWindowCollectionBehaviorParticipatesInCycle;""")
else:
    raise SystemExit("Unknown experiment")
