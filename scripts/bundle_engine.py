import pathlib, shutil, subprocess, plistlib
root=pathlib.Path('dist/视频快拆 1.0.1.app/Contents').resolve()
tools=root/'Tools'; tools.mkdir(exist_ok=True)
seen={}
def bundle(src):
    src=pathlib.Path(src).resolve()
    if str(src) in seen:return seen[str(src)]
    dst=tools/src.name; seen[str(src)]=dst; shutil.copy2(src,dst); dst.chmod(0o755)
    lines=subprocess.check_output(['otool','-L',str(src)],text=True).splitlines()[1:]
    for line in lines:
        dep=line.strip().split(' (')[0]
        if dep.startswith('/opt/homebrew/'):
            other=bundle(dep)
            subprocess.run(['install_name_tool','-change',dep,'@loader_path/'+other.name,str(dst)],check=True,capture_output=True)
    if dst.suffix=='.dylib':subprocess.run(['install_name_tool','-id','@loader_path/'+dst.name,str(dst)],check=True,capture_output=True)
    subprocess.run(['codesign','--force','--sign','-',str(dst)],check=True,capture_output=True)
    return dst
for n in ['ffmpeg','ffprobe']:bundle('/opt/homebrew/bin/'+n)
