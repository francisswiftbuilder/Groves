# Third-party software

Groves invokes a separately bundled Git executable. Groves's MIT license does not replace Git's license.

## Git 2.55.0

- Upstream: https://git-scm.com/ and https://www.kernel.org/pub/software/scm/git/
- License: GNU General Public License version 2, with notices for included components in the source archive.
- Unmodified corresponding source: `Git/share/groves-source/git-2.55.0.tar.xz` inside the application's `Contents/Resources` directory.
- License text: `Git/share/groves-source/Git-COPYING`.
- Build instructions: `Git/share/groves-source/build_bundled_git.sh`, with the build options used by Groves. The repository also provides runtime verification and embedding scripts under `script/`.
- Source SHA-256: `457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357`.

The executable links to macOS-provided system libraries, including libcurl and zlib. No Homebrew libraries are bundled. Git GUI, Tcl/Tk, Perl/Python tools, gettext translations, and legacy WebDAV push are not included.
