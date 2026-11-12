#!/usr/bin/env python3
"""Scan reachable Git blobs without printing secret values. Run in any Git repo.
This is a pattern-based audit, not a guarantee about all possible credentials.
"""
import json, re, subprocess, sys
patterns = {
 'private_key': re.compile(rb'-----BEGIN (?:EC |RSA |OPENSSH )?PRIVATE KEY-----'),
 'github_token': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'),
 'aws_access_key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
 'cloudflare_token_assignment': re.compile(rb'(?i)(?:CLOUDFLARE_API_TOKEN|CF_API_TOKEN|OPS_TOKEN|APNS_PRIVATE_KEY)\s*[=:]\s*[\x22\x27]([A-Za-z0-9_/-]{24,})[\x22\x27]'),
}
objects = subprocess.check_output(['git','rev-list','--objects','--all']).splitlines()
process = subprocess.Popen(['git','cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
findings=[]; scanned=0; excluded=[]
for entry in objects:
 oid,_,path=entry.partition(b' ')
 if path.startswith(b'design/assets/symbols/') or path in [b'design/index.html',b'contracts/fixtures/via-observed.json']:
  excluded.append(path.decode(errors='replace'))
 process.stdin.write(oid+b'\n');process.stdin.flush()
 header=process.stdout.readline().split()
 if len(header)!=3:raise RuntimeError(header)
 size=int(header[2]);data=process.stdout.read(size);process.stdout.read(1)
 if header[1]!=b'blob':continue
 scanned+=1
 for name,pattern in patterns.items():
  if pattern.search(data):findings.append({'pattern':name,'object':oid.decode(),'path':path.decode(errors='replace')})
process.stdin.close();process.wait()
report={'reachable_blobs_scanned':scanned,'credential_pattern_findings':findings,'excluded_material_paths':sorted(set(excluded))}
print(json.dumps(report,indent=2))
sys.exit(1 if findings or excluded else 0)
