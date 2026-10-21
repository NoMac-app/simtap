#!/bin/bash
# Turn the settled phone in ~/sue/cpu-probe.udid into a lean golden phone: background services an agent
# testing an app never needs are disabled inside the phone (persisted in its data, so clones inherit it),
# widgets leave the home screen, Reduce Motion is on.
u=$(cat ~/sue/cpu-probe.udid)
DISABLE="spotlightknowledged spotlightknowledged.updater searchd searchtoold hybridsearchd knowledgeconstructiond parsecd parsec-fbf suggestd
siriknowledged siriinferenced siri.context.service siri.acousticsignature assistantd assistant_service assistant_cdmd
intelligenceflowd intelligencecontextd intelligenceplatformd intelligencetasksd callintelligenced biomesyncd
newsd nanonewscd nanotimekitcompaniond mediaanalysisd mediaanalysisd.service photoanalysisd amsengagementd tipsd weatherd
fitnesscoachingd fitnessintelligenced finhealthd activitysharingd cloudphotod cloudsettingssyncagent icloudmailagent
icloudsubscriptionoptimizerd itunescloudd contacts.postersyncd"
n=0; for s in $DISABLE; do xcrun simctl spawn "$u" launchctl disable "system/com.apple.$s" 2>/dev/null && n=$((n+1)); xcrun simctl spawn "$u" launchctl bootout "system/com.apple.$s" >/dev/null 2>&1; done
echo "disabled $n services"
xcrun simctl spawn "$u" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
xcrun simctl spawn "$u" defaults write com.apple.Preferences KeyboardAutocorrection -bool false
xcrun simctl spawn "$u" defaults write com.apple.Preferences KeyboardPrediction -bool false
xcrun simctl spawn "$u" defaults write com.apple.Preferences KeyboardDidShowContinuousPathIntroduction -bool true
xcrun simctl shutdown "$u"; sleep 2
d=~/Library/Developer/CoreSimulator/Devices/$u/data/Library/SpringBoard
python3 - "$d" <<'PY'
import plistlib, sys, os
d = sys.argv[1]
def strip(items):
    out = []
    for it in items:
        if isinstance(it, dict):
            if it.get("elementType") == "widget" or any(isinstance(e, dict) and e.get("elementType") == "widget" for e in it.get("elements", [])): continue
            if "iconLists" in it: it["iconLists"] = [strip(page) for page in it["iconLists"]]
        out.append(it)
    return out
for name in ("IconState.plist", "DesiredIconState.plist"):
    p = os.path.join(d, name)
    if not os.path.exists(p): continue
    with open(p, "rb") as f: s = plistlib.load(f)
    before = str(s).count("'widget'")
    s["iconLists"] = [strip(page) for page in s.get("iconLists", [])]
    with open(p, "wb") as f: plistlib.dump(s, f, fmt=plistlib.FMT_BINARY)
    print(name, "widgets", before, "->", str(s).count("'widget'"))
PY
xcrun simctl rename "$u" gold-lean && echo "gold-lean = $u"
