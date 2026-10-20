import hashlib
import json
import sys
import urllib.request

t = sys.argv[1]
url = f"https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture={t}&image_type=jre&os=linux&vendor=eclipse"
HDR = {"User-Agent": "pf-hop-airflow-build"}  # python's default UA gets a 403
pkg = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=HDR)))[0]["binary"]["package"]
data = urllib.request.urlopen(urllib.request.Request(pkg["link"], headers=HDR)).read()
assert hashlib.sha256(data).hexdigest() == pkg["checksum"], "temurin checksum mismatch"
open("/tmp/jre.tgz", "wb").write(data)
print("installed temurin jre", pkg["name"])
