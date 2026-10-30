# Uso: abrir.py <firmado.shortcut> <salida-dir>: saca el plist del atajo firmado (AEA1 perfil 0).
import sys,struct,plistlib,subprocess,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
d=open(src,'rb').read(); assert d[:4]==b'AEA1'
n=struct.unpack('<I',d[8:12])[0]; auth=plistlib.loads(d[12:12+n])
cert=auth['SigningCertificateChain'][0]
open(f'{out}/leaf.der','wb').write(cert)
subprocess.run(['openssl','x509','-inform','DER','-in',f'{out}/leaf.der','-pubkey','-noout','-out',f'{out}/pub.pem'],check=True)
subprocess.run(['aea','decrypt','-i',src,'-o',f'{out}/payload.aar','-sign-pub',f'{out}/pub.pem'],check=True)
subprocess.run(['aa','extract','-i',f'{out}/payload.aar','-d',f'{out}/x'],check=True)
for r,_,fs in os.walk(f'{out}/x'):
    for f in fs: print(os.path.join(r,f))
