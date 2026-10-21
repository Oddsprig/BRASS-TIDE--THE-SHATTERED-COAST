"""Publish verified release ancestry to the owner's exact repository, without force or sign-in UI."""
from pathlib import Path
import argparse,json,os,re,subprocess,datetime
ROOT=Path(__file__).resolve().parents[1]
REMOTE='https://github.com/Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST.git'

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--check-only',action='store_true');ap.add_argument('--receipt',type=Path);args=ap.parse_args()
    env=os.environ.copy();env.update(GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='Never',GCM_GUI_PROMPT='0')
    def git(*command):
        result=subprocess.run(['git',*command],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        if result.returncode:raise RuntimeError((result.stdout+result.stderr).strip())
        return result.stdout.strip()
    receipt={'repository':REMOTE,'timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False}
    try:
        assert git('remote','get-url','origin')==REMOTE and git('remote','get-url','--push','origin')==REMOTE,'Unexpected repository destination.'
        assert git('symbolic-ref','--short','HEAD')=='main','Publish main only.'
        assert not git('status','--porcelain'),'Source checkout must be clean.'
        assert git('rev-parse','refs/tags/v0.001')=='8c71de042ce02cc119ba74965c869e905fe6a642','Original verified annotated tag changed.'
        tags=sorted(tag for tag in git('tag','--list').splitlines() if re.fullmatch(r'v\d+\.\d{3}',tag))
        assert tags
        for tag in tags:
            assert git('cat-file','-t','refs/tags/'+tag)=='tag','Each playable version needs an annotated tag.'
            git('merge-base','--is-ancestor',tag,'main')
        version=re.search(r'config/version="([^"]+)"',(ROOT/'game/project.godot').read_text(encoding='utf-8'))[1]
        assert 'v'+version in tags
        assert not git('diff','--name-only','v'+version,'main','--','game'),'Current game differs from its exact tag.'
        expected={'refs/heads/main':git('rev-parse','HEAD')}
        for tag in tags:expected['refs/tags/'+tag]=git('rev-parse','refs/tags/'+tag)
        receipt['expected_refs']=expected
        if args.check_only:print('PASS clean main, exact tagged game, original v0.001 and all release ancestry.');return 0
        print('Publishing main and '+', '.join(tags)+' without force or sign-in UI.',flush=True)
        git('push','--atomic','--set-upstream','--porcelain','origin',*[ref+':'+ref for ref in expected])
        actual={ref:sha for sha,ref in (line.split() for line in git('ls-remote','--refs','origin',*expected).splitlines())}
        assert actual==expected,'Remote refs do not match the exact local source.'
        receipt.update(published=True,remote_refs=actual)
        print('VERIFIED: GitHub main and every playable tag match local source.')
    except (AssertionError,RuntimeError,subprocess.TimeoutExpired) as error:
        receipt['error']=str(error);print('Publication not verified: '+str(error));return 1
    finally:
        if args.receipt and not args.check_only:
            args.receipt.parent.mkdir(parents=True,exist_ok=True)
            args.receipt.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return 0

if __name__=='__main__':raise SystemExit(main())
