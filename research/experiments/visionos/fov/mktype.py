import plistlib, sys, os, shutil
D = os.path.expanduser('~/Library/Developer/CoreSimulator/Profiles/DeviceTypes')
if sys.argv[1] == '--remove':
    shutil.rmtree(os.path.join(D, sys.argv[2] + '.simdevicetype')); sys.exit(0)
name, suf, w, h, hz = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
src = '/Library/Developer/CoreSimulator/Profiles/DeviceTypes/Apple Vision Pro.simdevicetype'
dst = os.path.join(D, name + '.simdevicetype'); os.makedirs(D, exist_ok=True)
if os.path.exists(dst): shutil.rmtree(dst)
shutil.copytree(src, dst, symlinks=True)
shutil.rmtree(os.path.join(dst, 'Contents/_CodeSignature'), ignore_errors=True)
ip = os.path.join(dst, 'Contents/Info.plist'); i = plistlib.load(open(ip, 'rb'))
i['CFBundleIdentifier'] = 'com.apple.CoreSimulator.SimDeviceType.ycode-test-' + suf; i['CFBundleName'] = name
plistlib.dump(i, open(ip, 'wb'))
cp = os.path.join(dst, 'Contents/Resources/capabilities.plist'); c = plistlib.load(open(cp, 'rb'))
def walk(o):
    if isinstance(o, dict):
        if o.get('displayType') == 'integrated': o['width'], o['height'], o['refreshRate'] = w, h, hz
        if 'main-screen-width' in o: o['main-screen-width'], o['main-screen-height'] = w, h
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(c); plistlib.dump(c, open(cp, 'wb'))
pp = os.path.join(dst, 'Contents/Resources/profile.plist'); pr = plistlib.load(open(pp, 'rb'))
pr.pop('createByDefaultForRuntimeVersions', None); plistlib.dump(pr, open(pp, 'wb'))
print('made', dst, i['CFBundleIdentifier'])
