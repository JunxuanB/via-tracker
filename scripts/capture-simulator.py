"""Capture DEBUG-only in-memory scenarios. Never modifies a user's saved journeys."""
import os,sys,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
device=sys.argv[1]
scenarios=sys.argv[2:] or ['empty','home','detail','connection','detail-dark','before','onway','waiting','interchange','second-leg','complete','reference','sync','offline','server-error','pending-update','midboard','crossday','timezone','no-position','settings','search','stations','boarding-picker','alighting-picker','departure','review','transfer-review','correct-stage','end-confirm']
out=root/'tmp/native-qa';out.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(*args,**kw):return subprocess.run(['xcrun','simctl',*args],env=kw.pop('env',env),capture_output=True,text=True,timeout=kw.pop('timeout',60),**kw)
for scenario in scenarios:
    run('terminate',device,'com.junxuanb.viatracker')
    launch=run('launch',device,'com.junxuanb.viatracker','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN',env=dict(env,SIMCTL_CHILD_VIA_QA_SCENARIO=scenario))
    if launch.returncode:raise RuntimeError(launch.stderr)
    time.sleep(6)
    screen=run('io',device,'screenshot',str(out/f'{scenario}-{device[:8]}.png'))
    if screen.returncode:raise RuntimeError(screen.stderr)
    print(scenario,flush=True)
